// FoldArc · libretro core host. See LibretroCore.h.
#import "LibretroCore.h"
#import "libretro.h"
// Vulkan is reached only through MoltenVK's vkGetInstanceProcAddr at run
// time (dlopen), so the app has no link-time Vulkan dependency.
#define VK_NO_PROTOTYPES 1
#import <vulkan/vulkan.h>
#import "libretro_vulkan.h"
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <atomic>
#import <mutex>
#import <condition_variable>
#import <chrono>
#import <vector>
#import <string>
#import <cstdarg>
#import <cmath>
#import <cstring>
#import <exception>
#import <algorithm>

namespace {

struct CoreAPI {
    void (*set_environment)(retro_environment_t) = nullptr;
    void (*set_video_refresh)(retro_video_refresh_t) = nullptr;
    void (*set_audio_sample)(retro_audio_sample_t) = nullptr;
    void (*set_audio_sample_batch)(retro_audio_sample_batch_t) = nullptr;
    void (*set_input_poll)(retro_input_poll_t) = nullptr;
    void (*set_input_state)(retro_input_state_t) = nullptr;
    void (*init)(void) = nullptr;
    void (*deinit)(void) = nullptr;
    unsigned (*api_version)(void) = nullptr;
    void (*get_system_info)(struct retro_system_info *) = nullptr;
    void (*get_system_av_info)(struct retro_system_av_info *) = nullptr;
    void (*set_controller_port_device)(unsigned, unsigned) = nullptr;
    void (*reset)(void) = nullptr;
    void (*run)(void) = nullptr;
    bool (*load_game)(const struct retro_game_info *) = nullptr;
    void (*unload_game)(void) = nullptr;
    size_t (*serialize_size)(void) = nullptr;
    bool (*serialize)(void *, size_t) = nullptr;
    bool (*unserialize)(const void *, size_t) = nullptr;
};

/// Input state written by the UI thread, read by the emulation thread.
struct InputState {
    std::atomic<uint32_t> buttons{0};
    /// Pressed since the previous poll: a tap shorter than a frame still
    /// reaches the core (START was tap-only before round 16, and a press and
    /// release between two polls was lost).
    std::atomic<uint32_t> latched{0};
    /// What the core reads until the next poll (retro_input_poll, once per frame).
    std::atomic<uint32_t> polled{0};
    std::atomic<int16_t> padX{0}, padY{0}, cstickX{0}, cstickY{0};
    std::atomic<int16_t> touchX{0}, touchY{0};
    std::atomic<bool> touchPressed{false};
};

/// Single-producer / single-consumer ring of interleaved stereo int16.
struct AudioRing {
    std::vector<int16_t> data;
    std::atomic<size_t> head{0}, tail{0};
    void reset(size_t frames) { data.assign(frames * 2, 0); head = 0; tail = 0; }
    size_t capacity() const { return data.size(); }
    size_t available() const { return (head.load() + capacity() - tail.load()) % capacity(); }
    void write(const int16_t *samples, size_t count) {
        size_t h = head.load();
        for (size_t i = 0; i < count; i++) {
            size_t next = (h + 1) % capacity();
            if (next == tail.load()) break;   // full: drop the rest
            data[h] = samples[i];
            h = next;
        }
        head.store(h);
    }
    size_t read(int16_t *out, size_t count) {
        size_t t = tail.load(), n = 0;
        while (n < count && t != head.load()) { out[n++] = data[t]; t = (t + 1) % capacity(); }
        tail.store(t);
        return n;
    }
};

/// Hardware rendering through the core's Vulkan renderer on MoltenVK.
///
/// The core negotiates the device itself (`create_device` in its
/// negotiation interface: it picks extensions and features and returns the
/// VkDevice/VkQueue, which then belong to the frontend). Each frame it renders
/// into one output image, hands it over with `set_image` and calls
/// video_refresh(RETRO_HW_FRAME_BUFFER_VALID). The host records a copy of that
/// image into a host-visible buffer and submits it on the same queue, so the
/// result can go down the same CGImage path as software frames. The core's
/// command worker may still be submitting the newest frame when video_refresh
/// arrives; the copy is ordered after everything already on the queue, so at
/// worst it shows the previous complete frame (never a torn one).
///
/// video_refresh does not wait for the copy (10-27, Simulator: waiting there
/// and presenting cost the emulation thread 0.4-2 ms of every frame). A
/// serial queue waits for its fence, copies the pixels out and presents them
/// while the emulation thread goes on with the next frame; two read-back
/// slots let the next copy be submitted while the previous one is still being
/// read out. The barrier after the copy keeps the core's later writes to the
/// image behind it on the GPU (what libretro asks of the frontend for
/// set_image), and wait_sync_index, which the core calls before it draws into
/// the image again or recreates it, waits for copies still pending.
struct ReadbackSlot {
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    VkFence fence = VK_NULL_HANDLE;
    VkBuffer buffer = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    void *mapped = nullptr;
    VkDeviceSize capacity = 0;
    unsigned width = 0, height = 0;     // the frame in flight
    VkFormat format = VK_FORMAT_UNDEFINED;
    /// Claimed by the emulation thread, then owned by the read-back queue
    /// until the pixels are copied out. Guarded by VulkanHost::slotLock.
    bool busy = false;
};
constexpr unsigned kReadbackSlots = 2;

struct VulkanHost {
    void *library = nullptr;
    PFN_vkGetInstanceProcAddr gipa = nullptr;
    PFN_vkGetDeviceProcAddr gdpa = nullptr;
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice gpu = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    uint32_t queueFamily = 0;
    std::string deviceName;
    std::mutex queueLock;
    struct retro_hw_render_interface_vulkan iface = {};
    // Latest image from set_image (emulation thread).
    struct retro_vulkan_image image = {};
    bool hasImage = false;
    std::vector<VkSemaphore> waitSemaphores;
    std::vector<VkPipelineStageFlags> waitStages;
    std::vector<VkCommandBuffer> extraCommands;
    /// A submit or a read-back failed: no more hardware frames (any thread).
    std::atomic<bool> lost{false};
    // Read-back resources (see ReadbackSlot).
    VkCommandPool pool = VK_NULL_HANDLE;    // the slots' command buffers come from here
    ReadbackSlot slots[kReadbackSlots];
    unsigned nextSlot = 0;                  // slots are claimed and finished in this order
    bool async = true;                      // finish read-backs on the read-back queue
    std::mutex slotLock;
    std::condition_variable slotFreed;
    // Diagnostics in mach ticks (FAFrameStats).
    std::atomic<uint64_t> syncWaitTicks{0}, slotWaitTicks{0};
    std::atomic<uint64_t> readbacks{0}, readbackWaitTicks{0}, readbackWaitMax{0};
    bool readbacksPending() const {         // with slotLock held
        for (const auto &slot : slots) if (slot.busy) return true;
        return false;
    }
#define FA_VK_FN(name) PFN_vk##name name = nullptr;
    FA_VK_FN(CreateInstance) FA_VK_FN(EnumerateInstanceExtensionProperties)
    FA_VK_FN(DestroyInstance) FA_VK_FN(EnumeratePhysicalDevices) FA_VK_FN(GetPhysicalDeviceProperties)
    FA_VK_FN(GetPhysicalDeviceMemoryProperties)
    FA_VK_FN(DestroyDevice) FA_VK_FN(DeviceWaitIdle) FA_VK_FN(CreateCommandPool) FA_VK_FN(DestroyCommandPool)
    FA_VK_FN(AllocateCommandBuffers) FA_VK_FN(ResetCommandBuffer) FA_VK_FN(BeginCommandBuffer)
    FA_VK_FN(EndCommandBuffer) FA_VK_FN(CmdPipelineBarrier) FA_VK_FN(CmdCopyImageToBuffer)
    FA_VK_FN(QueueSubmit) FA_VK_FN(CreateFence) FA_VK_FN(DestroyFence) FA_VK_FN(WaitForFences)
    FA_VK_FN(ResetFences) FA_VK_FN(CreateBuffer) FA_VK_FN(DestroyBuffer)
    FA_VK_FN(GetBufferMemoryRequirements) FA_VK_FN(AllocateMemory) FA_VK_FN(FreeMemory)
    FA_VK_FN(BindBufferMemory) FA_VK_FN(MapMemory) FA_VK_FN(UnmapMemory)
#undef FA_VK_FN
};

// retro_hw_render_interface_vulkan callbacks; `handle` is the VulkanHost.
static void fa_vk_set_image(void *handle, const struct retro_vulkan_image *image, uint32_t num_semaphores,
                            const VkSemaphore *semaphores, uint32_t /*src_queue_family: one family*/) {
    auto *vk = static_cast<VulkanHost *>(handle);
    if (!image) { vk->hasImage = false; return; }
    vk->image = *image;
    vk->hasImage = true;
    vk->waitSemaphores.assign(semaphores, semaphores + num_semaphores);
    vk->waitStages.assign(num_semaphores, VK_PIPELINE_STAGE_TRANSFER_BIT);
}
static uint32_t fa_vk_get_sync_index(void *) { return 0; }
static uint32_t fa_vk_get_sync_index_mask(void *) { return 1; }
static void fa_vk_set_command_buffers(void *handle, uint32_t num, const VkCommandBuffer *cmds) {
    auto *vk = static_cast<VulkanHost *>(handle);
    vk->extraCommands.insert(vk->extraCommands.end(), cmds, cmds + num);
}
// The core calls this before it draws into the image again, and before it
// recreates the image on a size change: wait for copies still reading it.
// Normally they finished while the core emulated the frame.
static void fa_vk_wait_sync_index(void *handle) {
    auto *vk = static_cast<VulkanHost *>(handle);
    std::unique_lock<std::mutex> lock(vk->slotLock);
    if (!vk->readbacksPending()) return;
    const uint64_t start = mach_absolute_time();
    // Bounded: a copy that never finishes marks the device lost after 2 s.
    vk->slotFreed.wait_for(lock, std::chrono::milliseconds(2500),
                           [vk] { return vk->lost.load() || !vk->readbacksPending(); });
    vk->syncWaitTicks += mach_absolute_time() - start;
}
static void fa_vk_lock_queue(void *handle) { static_cast<VulkanHost *>(handle)->queueLock.lock(); }
static void fa_vk_unlock_queue(void *handle) { static_cast<VulkanHost *>(handle)->queueLock.unlock(); }
static void fa_vk_set_signal_semaphore(void *, VkSemaphore) {}

} // namespace

@interface FALibretroCore () {
    void *_handle;
    CoreAPI _api;
    InputState _input;
    AudioRing _audio;
    std::mutex _frameLock;
    NSMutableData *_pendingFrame;       // buffer handed to the core for the next frame
    size_t _pendingPitch;
    CGSize _frameSize;
    NSThread *_thread;
    /// Held around every libretro entry point that touches emulation state
    /// (retro_run on the emulation thread; serialize/unserialize from callers),
    /// since the API requires them to be sequential.
    std::mutex _runLock;
    /// Work that needs the core to itself (save/load state), run by the
    /// emulation thread between frames while it is alive. Guarded by
    /// _commandLock, which also guards _thread/_shouldRun transitions.
    std::mutex _commandLock;
    NSMutableArray<dispatch_block_t> *_commands;
    std::atomic<bool> _shouldRun;
    std::atomic<bool> _paused;
    std::atomic<uint64_t> _presented;
    /// Audio counters since the last takeAudioStats (frames in from the core,
    /// frames read by the output, frames the output asked for but did not get,
    /// largest |sample| and sum of squares of what was read).
    std::atomic<uint64_t> _audioIn, _audioOut, _audioUnderrun, _audioSquares;
    std::atomic<uint64_t> _audioWritten;    // monotonic, for pacing
    std::atomic<uint32_t> _audioPeak;
    double _fps, _sampleRate;
    NSString *_systemDirectory, *_saveDirectory;
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *_options;
    NSString *_coreName, *_coreVersion;
    BOOL _coreLoaded, _gameLoaded;
    unsigned _language;
    // Hardware rendering (see VulkanHost).
    BOOL _vulkanEnabled;           // frontend allows a Vulkan context for the next load
    BOOL _hwRequested;             // the core asked for RETRO_HW_CONTEXT_VULKAN in retro_load_game
    BOOL _hwActive;                // device created, context_reset done
    struct retro_hw_render_callback _hwRender;
    const struct retro_hw_render_context_negotiation_interface_vulkan *_vkNegotiation;
    VulkanHost _vk;
    BOOL _vulkanAsyncReadback;     // see VulkanHost; read when the context is created
    BOOL _unthrottled;             // benchmark: no frame pacing
    std::atomic<double> _speed;    // 倍速: 1, 2, 4
    dispatch_queue_t _readbackQueue;
    // Emulation-thread timing for takeFrameStats (mach ticks).
    std::atomic<uint64_t> _runFrames, _runTicks, _runMaxTicks;
    NSString *_loadFailureMessage; // message the core showed while loading inside context_reset
    BOOL _capturingLoadMessages;
    // Core options: read on the emulation thread, changed from the UI
    // (setVariable). The previous dictionary is kept alive until the next
    // change, so a value string the core was just handed stays valid.
    std::mutex _variablesLock;
    std::atomic<bool> _variablesUpdated;
    NSDictionary<NSString *, NSString *> *_retiredVariables;
    // Microphone (see readMic:count:).
    std::atomic<bool> _micBlowingFlag;
    std::atomic<bool> _micActive;
    uint64_t _micLastRead;
    double _micOwed;    // samples due at 48 kHz and not yet handed over
    uint32_t _noiseState;
    float _noiseLow, _noiseEnvelope;
}
- (bool)environment:(unsigned)cmd data:(void *)data;
- (void)videoRefresh:(const void *)data width:(unsigned)w height:(unsigned)h pitch:(size_t)pitch;
- (void)presentFrame:(CGImageRef)frame width:(unsigned)w height:(unsigned)h;
- (void)vkReadBackFrameWidth:(unsigned)w height:(unsigned)h;
- (BOOL)vkCreateContext:(NSError **)error;
- (void)vkDestroyContext;
- (size_t)audioBatch:(const int16_t *)data frames:(size_t)frames;
- (int16_t)inputStatePort:(unsigned)port device:(unsigned)device index:(unsigned)index id:(unsigned)id;
- (void)log:(enum retro_log_level)level message:(NSString *)message;
- (void)pollInput;
- (void)micOpenedAtRate:(unsigned)rate;
- (void)micClosed;
- (void)setMicActive:(bool)active;
- (bool)micActive;
- (int)readMic:(int16_t *)samples count:(size_t)count;
@end

// libretro callbacks are plain C functions; route them to the singleton.
static FALibretroCore *gCore = nil;

static bool fa_environment(unsigned cmd, void *data) { return [gCore environment:cmd data:data]; }
static void fa_video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    [gCore videoRefresh:data width:width height:height pitch:pitch];
}
static void fa_audio_sample(int16_t left, int16_t right) {
    int16_t pair[2] = {left, right};
    [gCore audioBatch:pair frames:1];
}
static size_t fa_audio_sample_batch(const int16_t *data, size_t frames) { return [gCore audioBatch:data frames:frames]; }
static void fa_input_poll(void) { [gCore pollInput]; }

// Microphone interface (RETRO_ENVIRONMENT_GET_MICROPHONE_INTERFACE). One
// microphone; the handle only has to be a stable pointer.
struct retro_microphone { int unused; };
static retro_microphone_t gFAMicrophone;
static retro_microphone_t *fa_open_mic(const retro_microphone_params_t *params) {
    [gCore micOpenedAtRate:params ? params->rate : 0];
    return &gFAMicrophone;
}
static void fa_close_mic(retro_microphone_t *) { [gCore micClosed]; }
static bool fa_get_mic_params(const retro_microphone_t *, retro_microphone_params_t *params) {
    if (params) params->rate = 48000;
    return true;
}
static bool fa_set_mic_state(retro_microphone_t *, bool state) { [gCore setMicActive:state]; return true; }
static bool fa_get_mic_state(const retro_microphone_t *) { return [gCore micActive]; }
static int fa_read_mic(retro_microphone_t *, int16_t *samples, size_t count) { return [gCore readMic:samples count:count]; }
static int16_t fa_input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    return [gCore inputStatePort:port device:device index:index id:id];
}
static void fa_log(enum retro_log_level level, const char *fmt, ...) {
    char buffer[2048];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof buffer, fmt, args);
    va_end(args);
    [gCore log:level message:[NSString stringWithUTF8String:buffer] ?: @"?"];
}

@implementation FALibretroCore
@synthesize variables = _variables;

+ (FALibretroCore *)shared {
    static FALibretroCore *core;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ core = [[FALibretroCore alloc] init]; gCore = core; });
    return core;
}

- (instancetype)init {
    if ((self = [super init])) {
        _variables = @{};
        _options = [NSMutableArray array];
        _commands = [NSMutableArray array];
        _vulkanAsyncReadback = YES;
        _readbackQueue = dispatch_queue_create("FoldArc.vulkan.readback",
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
        _audio.reset(32768 * 2);     // ~2 s at 3DS rate
        _fps = 60; _sampleRate = 32728;
        _language = RETRO_LANGUAGE_ENGLISH;
        _coreName = @""; _coreVersion = @"";
        _speed.store(1.0);
    }
    return self;
}

- (BOOL)coreLoaded { return _coreLoaded; }
- (BOOL)gameLoaded { return _gameLoaded; }
- (BOOL)running { return _thread != nil && _shouldRun.load() && !_paused.load(); }
- (double)fps { return _fps; }
- (double)sampleRate { return _sampleRate; }
- (CGSize)frameSize { return _frameSize; }
- (NSString *)coreName { return _coreName; }
- (NSString *)coreVersion { return _coreVersion; }
- (uint64_t)presentedFrames { return _presented.load(); }
- (NSArray<NSDictionary<NSString *, NSString *> *> *)publishedOptions { return [_options copy]; }
- (BOOL)vulkanEnabled { return _vulkanEnabled; }
- (void)setVulkanEnabled:(BOOL)enabled { _vulkanEnabled = enabled; }
- (BOOL)vulkanAsyncReadback { return _vulkanAsyncReadback; }
- (void)setVulkanAsyncReadback:(BOOL)enabled { _vulkanAsyncReadback = enabled; }
- (BOOL)unthrottled { return _unthrottled; }
- (void)setUnthrottled:(BOOL)value { _unthrottled = value; }
- (double)speed { return _speed.load(); }
- (void)setSpeed:(double)value { _speed.store(std::max(1.0, std::min(8.0, value))); }
- (NSString *)hardwareRenderer {
    return _hwActive ? [NSString stringWithFormat:@"Vulkan · %s", _vk.deviceName.c_str()] : nil;
}

#pragma mark - Loading

static NSError *FAError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"FoldArc.LibretroCore" code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (BOOL)loadCoreAtPath:(NSString *)path error:(NSError **)error {
    if (_coreLoaded) return YES;
    _handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!_handle) {
        if (error) *error = FAError(1, [NSString stringWithFormat:@"dlopen failed: %s", dlerror() ?: "?"]);
        return NO;
    }
#define FA_SYM(field, name) do { \
        *(void **)&_api.field = dlsym(_handle, name); \
        if (!_api.field) { if (error) *error = FAError(2, [NSString stringWithFormat:@"missing symbol %s", name]); return NO; } \
    } while (0)
    FA_SYM(set_environment, "retro_set_environment");
    FA_SYM(set_video_refresh, "retro_set_video_refresh");
    FA_SYM(set_audio_sample, "retro_set_audio_sample");
    FA_SYM(set_audio_sample_batch, "retro_set_audio_sample_batch");
    FA_SYM(set_input_poll, "retro_set_input_poll");
    FA_SYM(set_input_state, "retro_set_input_state");
    FA_SYM(init, "retro_init");
    FA_SYM(deinit, "retro_deinit");
    FA_SYM(api_version, "retro_api_version");
    FA_SYM(get_system_info, "retro_get_system_info");
    FA_SYM(get_system_av_info, "retro_get_system_av_info");
    FA_SYM(set_controller_port_device, "retro_set_controller_port_device");
    FA_SYM(reset, "retro_reset");
    FA_SYM(run, "retro_run");
    FA_SYM(load_game, "retro_load_game");
    FA_SYM(unload_game, "retro_unload_game");
    FA_SYM(serialize_size, "retro_serialize_size");
    FA_SYM(serialize, "retro_serialize");
    FA_SYM(unserialize, "retro_unserialize");
#undef FA_SYM
    if (_api.api_version() != RETRO_API_VERSION) {
        if (error) *error = FAError(3, [NSString stringWithFormat:@"libretro API %u, expected %u", _api.api_version(), RETRO_API_VERSION]);
        return NO;
    }
    struct retro_system_info info = {};
    _api.get_system_info(&info);
    _coreName = info.library_name ? @(info.library_name) : @"core";
    _coreVersion = info.library_version ? @(info.library_version) : @"";
    // Order matters: environment first, then the other callbacks, then init.
    _api.set_environment(fa_environment);
    _api.set_video_refresh(fa_video_refresh);
    _api.set_audio_sample(fa_audio_sample);
    _api.set_audio_sample_batch(fa_audio_sample_batch);
    _api.set_input_poll(fa_input_poll);
    _api.set_input_state(fa_input_state);
    _api.init();
    _coreLoaded = YES;
    [self log:RETRO_LOG_INFO message:[NSString stringWithFormat:@"core loaded: %@ %@", _coreName, _coreVersion]];
    return YES;
}

- (BOOL)loadGameAtPath:(NSString *)path systemDirectory:(NSString *)systemDirectory saveDirectory:(NSString *)saveDirectory error:(NSError **)error {
    if (!_coreLoaded) { if (error) *error = FAError(4, @"core not loaded"); return NO; }
    if (_gameLoaded) [self stop];
    _systemDirectory = [systemDirectory copy];
    _saveDirectory = [saveDirectory copy];
    [[NSFileManager defaultManager] createDirectoryAtPath:systemDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:saveDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    struct retro_game_info game = {};
    game.path = path.fileSystemRepresentation;
    game.data = nullptr; game.size = 0; game.meta = nullptr;   // Azahar reads from the path (need_fullpath)
    _presented = 0;
    _hwRequested = NO; _hwActive = NO; _vkNegotiation = nullptr; _hwRender = {};
    if (!_api.load_game(&game)) {
        if (error) *error = FAError(5, @"retro_load_game failed (see core log)");
        return NO;
    }
    if (_hwRequested) {
        // With a hardware context Azahar only records the path in
        // retro_load_game; the game itself loads inside context_reset, once
        // the frontend has a device for it.
        NSError *vkError = nil;
        if (![self vkCreateContext:&vkError]) {
            _api.unload_game();
            [self vkDestroyContext];
            if (error) *error = vkError ?: FAError(20, @"Vulkan context unavailable");
            return NO;
        }
        _hwActive = YES;
        _loadFailureMessage = nil;
        _capturingLoadMessages = YES;
        // The core's Vulkan setup throws std::runtime_error on an unusable
        // device; keep that from unwinding through Objective-C frames.
        try {
            if (_hwRender.context_reset) _hwRender.context_reset();
        } catch (const std::exception &e) {
            _loadFailureMessage = [NSString stringWithFormat:@"Vulkan renderer failed to start: %s", e.what()];
        } catch (...) {
            _loadFailureMessage = @"Vulkan renderer failed to start (unknown exception)";
        }
        _capturingLoadMessages = NO;
        if (_loadFailureMessage) {
            if (_hwRender.context_destroy) _hwRender.context_destroy();
            _api.unload_game();
            _hwActive = NO;
            [self vkDestroyContext];
            if (error) *error = FAError(21, _loadFailureMessage);
            return NO;
        }
    }
    struct retro_system_av_info av = {};
    _api.get_system_av_info(&av);
    _fps = av.timing.fps > 0 ? av.timing.fps : 60;
    _sampleRate = av.timing.sample_rate > 0 ? av.timing.sample_rate : 32728;
    _frameSize = CGSizeMake(av.geometry.base_width, av.geometry.base_height);
    _api.set_controller_port_device(0, RETRO_DEVICE_JOYPAD);
    _gameLoaded = YES;
    [self log:RETRO_LOG_INFO message:[NSString stringWithFormat:@"game loaded: %gx%g @ %.2f fps, %.0f Hz, %@", _frameSize.width, _frameSize.height, _fps, _sampleRate, self.hardwareRenderer ?: @"software renderer"]];
    return YES;
}

#pragma mark - Vulkan (MoltenVK)

- (BOOL)vkLoadLibrary:(NSError **)error {
    if (_vk.gipa) return YES;
    NSString *path = [[NSBundle mainBundle].privateFrameworksPath stringByAppendingPathComponent:@"MoltenVK.framework/MoltenVK"];
    if (!_vk.library) _vk.library = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!_vk.library) {
        if (error) *error = FAError(22, [NSString stringWithFormat:@"MoltenVK not loadable: %s", dlerror() ?: "?"]);
        return NO;
    }
    _vk.gipa = (PFN_vkGetInstanceProcAddr)dlsym(_vk.library, "vkGetInstanceProcAddr");
    if (_vk.gipa) {
        _vk.CreateInstance = (PFN_vkCreateInstance)_vk.gipa(VK_NULL_HANDLE, "vkCreateInstance");
        _vk.EnumerateInstanceExtensionProperties = (PFN_vkEnumerateInstanceExtensionProperties)_vk.gipa(VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties");
    }
    if (!_vk.gipa || !_vk.CreateInstance || !_vk.EnumerateInstanceExtensionProperties) {
        _vk.gipa = nullptr;
        if (error) *error = FAError(23, @"MoltenVK has no vkGetInstanceProcAddr / vkCreateInstance");
        return NO;
    }
    return YES;
}

/// Creates the VkInstance and picks the (only) physical device.
- (BOOL)vkCreateInstanceWithApp:(const VkApplicationInfo *)app error:(NSError **)error {
    uint32_t count = 0;
    _vk.EnumerateInstanceExtensionProperties(nullptr, &count, nullptr);
    std::vector<VkExtensionProperties> available(count);
    if (count) _vk.EnumerateInstanceExtensionProperties(nullptr, &count, available.data());
    auto has = [&](const char *name) {
        return std::any_of(available.begin(), available.end(), [&](const VkExtensionProperties &p) { return strcmp(p.extensionName, name) == 0; });
    };
    std::vector<const char *> extensions;
    VkInstanceCreateFlags flags = 0;
    if (has(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)) {
        extensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }
    if (has(VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME)) extensions.push_back(VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME);
    VkApplicationInfo fallback = {VK_STRUCTURE_TYPE_APPLICATION_INFO, nullptr, "FoldArc", 1, "FoldArc", 1, VK_API_VERSION_1_1};
    VkInstanceCreateInfo info = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, nullptr, flags, app ? app : &fallback, 0, nullptr,
                                 0, nullptr};
#if TARGET_OS_SIMULATOR
    // The Simulator's Metal driver forwards every argument-encoder call to the
    // host as a synchronous XPC round trip; with MoltenVK's default Metal
    // argument buffers, vkUpdateDescriptorSets took ~75 % of the emulation
    // thread (10-27 samples). Bind resources directly there; devices
    // keep the default. (MoltenVK reads its environment variables at launch,
    // so this goes through VK_EXT_layer_settings.)
    static const VkBool32 noArgumentBuffers = VK_FALSE;
    static const VkLayerSettingEXT simulatorSettings[] = {
        {"MoltenVK", "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", VK_LAYER_SETTING_TYPE_BOOL32_EXT, 1, &noArgumentBuffers},
    };
    static const VkLayerSettingsCreateInfoEXT layerSettings = {
        VK_STRUCTURE_TYPE_LAYER_SETTINGS_CREATE_INFO_EXT, nullptr, 1, simulatorSettings};
    if (has(VK_EXT_LAYER_SETTINGS_EXTENSION_NAME)) {
        extensions.push_back(VK_EXT_LAYER_SETTINGS_EXTENSION_NAME);
        info.pNext = &layerSettings;
    }
#endif
    info.enabledExtensionCount = (uint32_t)extensions.size();
    info.ppEnabledExtensionNames = extensions.data();
    VkResult result = _vk.CreateInstance(&info, nullptr, &_vk.instance);
    if (result != VK_SUCCESS) {
        _vk.instance = VK_NULL_HANDLE;
        if (error) *error = FAError(24, [NSString stringWithFormat:@"vkCreateInstance failed (%d)", (int)result]);
        return NO;
    }
#define FA_VK_INSTANCE(name) _vk.name = (PFN_vk##name)_vk.gipa(_vk.instance, "vk" #name)
    FA_VK_INSTANCE(DestroyInstance); FA_VK_INSTANCE(EnumeratePhysicalDevices);
    FA_VK_INSTANCE(GetPhysicalDeviceProperties); FA_VK_INSTANCE(GetPhysicalDeviceMemoryProperties);
#undef FA_VK_INSTANCE
    _vk.gdpa = (PFN_vkGetDeviceProcAddr)_vk.gipa(_vk.instance, "vkGetDeviceProcAddr");
    uint32_t gpus = 0;
    if (_vk.EnumeratePhysicalDevices) _vk.EnumeratePhysicalDevices(_vk.instance, &gpus, nullptr);
    if (gpus == 0 || !_vk.gdpa || !_vk.GetPhysicalDeviceProperties) {
        if (error) *error = FAError(25, @"MoltenVK reports no Vulkan device");
        return NO;
    }
    std::vector<VkPhysicalDevice> devices(gpus);
    _vk.EnumeratePhysicalDevices(_vk.instance, &gpus, devices.data());
    _vk.gpu = devices[0];
    VkPhysicalDeviceProperties properties = {};
    _vk.GetPhysicalDeviceProperties(_vk.gpu, &properties);
    _vk.deviceName = properties.deviceName;
    return YES;
}

- (NSString *)probeVulkanWithError:(NSError **)error {
    if (_hwActive) return [NSString stringWithUTF8String:_vk.deviceName.c_str()];
    if (![self vkLoadLibrary:error]) return nil;
    if (![self vkCreateInstanceWithApp:nullptr error:error]) { [self vkDestroyContext]; return nil; }
    NSString *name = [NSString stringWithUTF8String:_vk.deviceName.c_str()];
    [self vkDestroyContext];
    return name;
}

- (BOOL)vkCreateContext:(NSError **)error {
    if (![self vkLoadLibrary:error]) return NO;
    if (!_vkNegotiation || !_vkNegotiation->create_device) {
        if (error) *error = FAError(26, @"core asked for Vulkan without a device negotiation interface");
        return NO;
    }
    const VkApplicationInfo *app = _vkNegotiation->get_application_info ? _vkNegotiation->get_application_info() : nullptr;
    if (![self vkCreateInstanceWithApp:app error:error]) return NO;
    struct retro_vulkan_context context = {};
    // No surface and no extra extensions: the host only copies the image back.
    if (!_vkNegotiation->create_device(&context, _vk.instance, _vk.gpu, VK_NULL_HANDLE, _vk.gipa,
                                       nullptr, 0, nullptr, 0, nullptr) || !context.device || !context.queue) {
        if (error) *error = FAError(27, @"the core could not create a Vulkan device on MoltenVK");
        return NO;
    }
    if (context.gpu) _vk.gpu = context.gpu;
    _vk.device = context.device;
    _vk.queue = context.queue;
    _vk.queueFamily = context.queue_family_index;
#define FA_VK_DEVICE(name) _vk.name = (PFN_vk##name)_vk.gdpa(_vk.device, "vk" #name)
    FA_VK_DEVICE(DestroyDevice); FA_VK_DEVICE(DeviceWaitIdle); FA_VK_DEVICE(CreateCommandPool);
    FA_VK_DEVICE(DestroyCommandPool); FA_VK_DEVICE(AllocateCommandBuffers); FA_VK_DEVICE(ResetCommandBuffer);
    FA_VK_DEVICE(BeginCommandBuffer); FA_VK_DEVICE(EndCommandBuffer); FA_VK_DEVICE(CmdPipelineBarrier);
    FA_VK_DEVICE(CmdCopyImageToBuffer); FA_VK_DEVICE(QueueSubmit); FA_VK_DEVICE(CreateFence);
    FA_VK_DEVICE(DestroyFence); FA_VK_DEVICE(WaitForFences); FA_VK_DEVICE(ResetFences);
    FA_VK_DEVICE(CreateBuffer); FA_VK_DEVICE(DestroyBuffer); FA_VK_DEVICE(GetBufferMemoryRequirements);
    FA_VK_DEVICE(AllocateMemory); FA_VK_DEVICE(FreeMemory); FA_VK_DEVICE(BindBufferMemory);
    FA_VK_DEVICE(MapMemory); FA_VK_DEVICE(UnmapMemory);
#undef FA_VK_DEVICE
    if (!_vk.QueueSubmit || !_vk.CmdCopyImageToBuffer || !_vk.MapMemory || !_vk.DestroyDevice) {
        if (error) *error = FAError(28, @"MoltenVK is missing device functions");
        return NO;
    }
    VkCommandPoolCreateInfo poolInfo = {VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, nullptr,
                                        VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, _vk.queueFamily};
    if (_vk.CreateCommandPool(_vk.device, &poolInfo, nullptr, &_vk.pool) != VK_SUCCESS) {
        _vk.pool = VK_NULL_HANDLE;
        if (error) *error = FAError(29, @"could not create the read-back command pool");
        return NO;
    }
    VkFenceCreateInfo fenceInfo = {VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, nullptr, 0};
    VkCommandBufferAllocateInfo allocInfo = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, nullptr, _vk.pool,
                                             VK_COMMAND_BUFFER_LEVEL_PRIMARY, 1};
    for (auto &slot : _vk.slots) {
        if (_vk.CreateFence(_vk.device, &fenceInfo, nullptr, &slot.fence) != VK_SUCCESS) slot.fence = VK_NULL_HANDLE;
        if (_vk.AllocateCommandBuffers(_vk.device, &allocInfo, &slot.cmd) != VK_SUCCESS) slot.cmd = VK_NULL_HANDLE;
        if (!slot.fence || !slot.cmd) {
            if (error) *error = FAError(29, @"could not create the read-back fences / command buffers");
            return NO;
        }
    }
    _vk.nextSlot = 0;
    _vk.async = _vulkanAsyncReadback;
    auto &i = _vk.iface;
    i = {};
    i.interface_type = RETRO_HW_RENDER_INTERFACE_VULKAN;
    i.interface_version = RETRO_HW_RENDER_INTERFACE_VULKAN_VERSION;
    i.handle = &_vk;
    i.instance = _vk.instance;
    i.gpu = _vk.gpu;
    i.device = _vk.device;
    i.get_device_proc_addr = _vk.gdpa;
    i.get_instance_proc_addr = _vk.gipa;
    i.queue = _vk.queue;
    i.queue_index = _vk.queueFamily;
    i.set_image = fa_vk_set_image;
    i.get_sync_index = fa_vk_get_sync_index;
    i.get_sync_index_mask = fa_vk_get_sync_index_mask;
    i.set_command_buffers = fa_vk_set_command_buffers;
    i.wait_sync_index = fa_vk_wait_sync_index;
    i.lock_queue = fa_vk_lock_queue;
    i.unlock_queue = fa_vk_unlock_queue;
    i.set_signal_semaphore = fa_vk_set_signal_semaphore;
    _vk.hasImage = false;
    _vk.lost = false;
    [self log:RETRO_LOG_INFO message:[NSString stringWithFormat:@"Vulkan device ready: %s (queue family %u, %s read-back)",
                                      _vk.deviceName.c_str(), _vk.queueFamily, _vk.async ? "asynchronous" : "synchronous"]];
    return YES;
}

/// Destroys everything the host created (the core has already released its
/// own objects in retro_unload_game). Safe to call on a partial context.
- (void)vkDestroyContext {
    if (_vk.device) {
        if (_vk.DeviceWaitIdle) _vk.DeviceWaitIdle(_vk.device);
        // The GPU is idle, so every queued read-back can finish now; let them
        // before their buffers and fences go away.
        dispatch_sync(_readbackQueue, ^{});
        for (auto &slot : _vk.slots) {
            [self vkFreeBufferOfSlot:&slot];
            if (slot.fence && _vk.DestroyFence) _vk.DestroyFence(_vk.device, slot.fence, nullptr);
        }
        // Destroying the pool also frees the slots' command buffers.
        if (_vk.pool && _vk.DestroyCommandPool) _vk.DestroyCommandPool(_vk.device, _vk.pool, nullptr);
        if (_vk.DestroyDevice) _vk.DestroyDevice(_vk.device, nullptr);
    }
    if (_vk.instance && _vk.DestroyInstance) _vk.DestroyInstance(_vk.instance, nullptr);
    {
        std::lock_guard<std::mutex> lock(_vk.slotLock);
        for (auto &slot : _vk.slots) slot = ReadbackSlot{};
    }
    _vk.nextSlot = 0;
    _vk.pool = VK_NULL_HANDLE;
    _vk.device = VK_NULL_HANDLE; _vk.queue = VK_NULL_HANDLE; _vk.instance = VK_NULL_HANDLE; _vk.gpu = VK_NULL_HANDLE;
    _vk.hasImage = false; _vk.waitSemaphores.clear(); _vk.waitStages.clear(); _vk.extraCommands.clear();
    _vk.iface = {};
}

- (void)vkFreeBufferOfSlot:(ReadbackSlot *)slot {
    if (slot->mapped && _vk.UnmapMemory) _vk.UnmapMemory(_vk.device, slot->memory);
    if (slot->buffer && _vk.DestroyBuffer) _vk.DestroyBuffer(_vk.device, slot->buffer, nullptr);
    if (slot->memory && _vk.FreeMemory) _vk.FreeMemory(_vk.device, slot->memory, nullptr);
    slot->buffer = VK_NULL_HANDLE; slot->memory = VK_NULL_HANDLE; slot->mapped = nullptr; slot->capacity = 0;
}

/// Grows a slot's buffer to `size` (emulation thread, slot claimed).
- (BOOL)vkEnsureBuffer:(VkDeviceSize)size slot:(ReadbackSlot *)slot {
    if (slot->buffer && slot->capacity >= size) return YES;
    [self vkFreeBufferOfSlot:slot];
    VkBufferCreateInfo info = {VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, nullptr, 0, size,
                               VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_SHARING_MODE_EXCLUSIVE, 0, nullptr};
    if (_vk.CreateBuffer(_vk.device, &info, nullptr, &slot->buffer) != VK_SUCCESS) { slot->buffer = VK_NULL_HANDLE; return NO; }
    VkMemoryRequirements req = {};
    _vk.GetBufferMemoryRequirements(_vk.device, slot->buffer, &req);
    VkPhysicalDeviceMemoryProperties props = {};
    _vk.GetPhysicalDeviceMemoryProperties(_vk.gpu, &props);
    uint32_t type = UINT32_MAX;
    const VkMemoryPropertyFlags wanted[] = {
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    };
    for (VkMemoryPropertyFlags flags : wanted) {
        for (uint32_t t = 0; t < props.memoryTypeCount && type == UINT32_MAX; t++) {
            if ((req.memoryTypeBits & (1u << t)) && (props.memoryTypes[t].propertyFlags & flags) == flags) type = t;
        }
        if (type != UINT32_MAX) break;
    }
    VkMemoryAllocateInfo alloc = {VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, nullptr, req.size, type};
    bool ok = type != UINT32_MAX;
    if (ok && _vk.AllocateMemory(_vk.device, &alloc, nullptr, &slot->memory) != VK_SUCCESS) { slot->memory = VK_NULL_HANDLE; ok = false; }
    if (ok && _vk.BindBufferMemory(_vk.device, slot->buffer, slot->memory, 0) != VK_SUCCESS) ok = false;
    if (ok && _vk.MapMemory(_vk.device, slot->memory, 0, VK_WHOLE_SIZE, 0, &slot->mapped) != VK_SUCCESS) { slot->mapped = nullptr; ok = false; }
    if (!ok) {
        [self log:RETRO_LOG_ERROR message:@"Vulkan: could not allocate host-visible read-back memory"];
        [self vkFreeBufferOfSlot:slot];
        return NO;
    }
    slot->capacity = size;
    return YES;
}

/// Copies the image the core handed over with set_image into a read-back
/// slot (emulation thread, inside video_refresh). The rest (fence, pixels,
/// present) happens on _readbackQueue, so this returns once the copy is
/// submitted; with vulkanAsyncReadback off it is all done here, as before 10-27.
- (void)vkReadBackFrameWidth:(unsigned)w height:(unsigned)h {
    if (!_vk.hasImage || !_vk.device || _vk.lost) return;
    ReadbackSlot *slot = [self vkClaimSlot];
    if (!slot) return;
    if (![self vkSubmitCopyInto:slot width:w height:h]) { [self vkReleaseSlot:slot]; return; }
    if (_vk.async) {
        dispatch_async(_readbackQueue, ^{ [self vkFinishReadback:slot]; });
    } else {
        [self vkFinishReadback:slot];
    }
}

/// The oldest slot, which the next copy goes into. It is still busy only when
/// the GPU or the read-back queue is a whole frame behind; then wait for it
/// (as the synchronous path always did) rather than drop the frame.
- (ReadbackSlot *)vkClaimSlot {
    std::unique_lock<std::mutex> lock(_vk.slotLock);
    ReadbackSlot *slot = &_vk.slots[_vk.nextSlot];
    if (slot->busy && !_vk.lost) {
        const uint64_t start = mach_absolute_time();
        _vk.slotFreed.wait_for(lock, std::chrono::milliseconds(2500), [&] { return !slot->busy || _vk.lost.load(); });
        _vk.slotWaitTicks += mach_absolute_time() - start;
    }
    if (slot->busy || _vk.lost) return nullptr;
    slot->busy = true;
    _vk.nextSlot = (_vk.nextSlot + 1) % kReadbackSlots;
    return slot;
}

- (void)vkReleaseSlot:(ReadbackSlot *)slot {
    {
        std::lock_guard<std::mutex> lock(_vk.slotLock);
        slot->busy = false;
    }
    _vk.slotFreed.notify_all();
}

/// Records and submits the copy into `slot` (emulation thread, slot claimed).
- (BOOL)vkSubmitCopyInto:(ReadbackSlot *)slot width:(unsigned)w height:(unsigned)h {
    const VkImage image = _vk.image.create_info.image;
    const VkImageLayout layout = _vk.image.image_layout;
    const VkImageSubresourceRange range = _vk.image.create_info.subresourceRange;
    const VkDeviceSize size = (VkDeviceSize)w * h * 4;
    if (![self vkEnsureBuffer:size slot:slot]) return NO;
    _vk.ResetCommandBuffer(slot->cmd, 0);
    VkCommandBufferBeginInfo begin = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, nullptr, VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, nullptr};
    _vk.BeginCommandBuffer(slot->cmd, &begin);
    VkImageMemoryBarrier toTransfer = {VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, nullptr,
        VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_SHADER_WRITE_BIT | VK_ACCESS_TRANSFER_WRITE_BIT,
        VK_ACCESS_TRANSFER_READ_BIT, layout, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        VK_QUEUE_FAMILY_IGNORED, VK_QUEUE_FAMILY_IGNORED, image, range};
    _vk.CmdPipelineBarrier(slot->cmd, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0,
                           0, nullptr, 0, nullptr, 1, &toTransfer);
    VkBufferImageCopy region = {};
    region.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, range.baseMipLevel, range.baseArrayLayer, 1};
    region.imageExtent = {w, h, 1};
    _vk.CmdCopyImageToBuffer(slot->cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, slot->buffer, 1, &region);
    VkImageMemoryBarrier restore = {VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, nullptr,
        VK_ACCESS_TRANSFER_READ_BIT, VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_SHADER_READ_BIT,
        VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, layout,
        VK_QUEUE_FAMILY_IGNORED, VK_QUEUE_FAMILY_IGNORED, image, range};
    VkBufferMemoryBarrier toHost = {VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER, nullptr,
        VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_HOST_READ_BIT,
        VK_QUEUE_FAMILY_IGNORED, VK_QUEUE_FAMILY_IGNORED, slot->buffer, 0, VK_WHOLE_SIZE};
    _vk.CmdPipelineBarrier(slot->cmd, VK_PIPELINE_STAGE_TRANSFER_BIT,
                           VK_PIPELINE_STAGE_ALL_COMMANDS_BIT | VK_PIPELINE_STAGE_HOST_BIT, 0,
                           0, nullptr, 1, &toHost, 1, &restore);
    _vk.EndCommandBuffer(slot->cmd);
    std::vector<VkCommandBuffer> commands = _vk.extraCommands;
    commands.push_back(slot->cmd);
    _vk.extraCommands.clear();
    VkSubmitInfo submit = {VK_STRUCTURE_TYPE_SUBMIT_INFO, nullptr,
        (uint32_t)_vk.waitSemaphores.size(), _vk.waitSemaphores.data(), _vk.waitStages.data(),
        (uint32_t)commands.size(), commands.data(), 0, nullptr};
    VkResult result;
    {
        std::lock_guard<std::mutex> queue(_vk.queueLock);
        result = _vk.QueueSubmit(_vk.queue, 1, &submit, slot->fence);
    }
    _vk.waitSemaphores.clear(); _vk.waitStages.clear();
    if (result != VK_SUCCESS) {
        [self log:RETRO_LOG_ERROR message:[NSString stringWithFormat:@"Vulkan: read-back submit failed (%d)", (int)result]];
        if (result == VK_ERROR_DEVICE_LOST) _vk.lost = true;
        return NO;
    }
    slot->width = w; slot->height = h; slot->format = _vk.image.create_info.format;
    return YES;
}

/// Waits for a submitted copy, copies the pixels out of the slot, frees it and
/// presents the frame (read-back queue; emulation thread when synchronous).
- (void)vkFinishReadback:(ReadbackSlot *)slot {
    @autoreleasepool {
        const uint64_t start = mach_absolute_time();
        const VkResult result = _vk.WaitForFences(_vk.device, 1, &slot->fence, VK_TRUE, 2000000000ull);
        const uint64_t waited = mach_absolute_time() - start;
        _vk.readbacks++;
        _vk.readbackWaitTicks += waited;
        uint64_t longest = _vk.readbackWaitMax.load();
        while (waited > longest && !_vk.readbackWaitMax.compare_exchange_weak(longest, waited)) {}
        if (result != VK_SUCCESS) {
            // The fence may still be pending; it cannot be reset or reused safely.
            [self log:RETRO_LOG_ERROR message:[NSString stringWithFormat:@"Vulkan: read-back did not finish (%d); stopping hardware frames", (int)result]];
            _vk.lost = true;
            [self vkReleaseSlot:slot];
            return;
        }
        _vk.ResetFences(_vk.device, 1, &slot->fence);
        const unsigned w = slot->width, h = slot->height;
        const VkFormat format = slot->format;
        NSData *pixels = [NSData dataWithBytes:slot->mapped length:(NSUInteger)w * h * 4];
        [self vkReleaseSlot:slot];
        const bool bgra = format == VK_FORMAT_B8G8R8A8_UNORM || format == VK_FORMAT_B8G8R8A8_SRGB;
        CGBitmapInfo info = bgra ? ((CGBitmapInfo)kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaNoneSkipFirst)
                                 : ((CGBitmapInfo)kCGBitmapByteOrderDefault | (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGImageRef frame = CGImageCreate(w, h, 8, 32, (size_t)w * 4, space, info, provider, nullptr, false, kCGRenderingIntentDefault);
        CGColorSpaceRelease(space);
        CGDataProviderRelease(provider);
        if (frame) { [self presentFrame:frame width:w height:h]; CGImageRelease(frame); }
    }
}

#pragma mark - Run loop

- (void)start { [self startThreadPaused:NO]; }
- (void)startPaused { [self startThreadPaused:YES]; }
- (void)startThreadPaused:(BOOL)paused {
    if (!_gameLoaded) return;
    std::lock_guard<std::mutex> g(_commandLock);
    if (_thread) return;
    _shouldRun = true; _paused = paused;
    _thread = [[NSThread alloc] initWithTarget:self selector:@selector(runLoop) object:nil];
    _thread.name = @"FoldArc.libretro";
    _thread.qualityOfService = NSQualityOfServiceUserInteractive;
    _thread.threadPriority = 1.0;
    [_thread start];
}
- (void)pause { _paused = true; }
- (void)resume { _paused = false; }
- (void)stop {
    NSThread *t;
    {
        std::lock_guard<std::mutex> g(_commandLock);
        _shouldRun = false;
        t = _thread;
        _thread = nil;
    }
    while (t && !t.isFinished) { [NSThread sleepForTimeInterval:0.002]; }
    [self drainCommands];   // anything queued before the thread saw the flag
    if (_gameLoaded) {
        // The order a libretro frontend keeps: context_destroy, then retro_unload_game
        // (which tears down the core's renderer on our still-alive device),
        // then the frontend's own device and instance.
        if (_hwActive && _hwRender.context_destroy) _hwRender.context_destroy();
        _api.unload_game();
        _gameLoaded = NO;
    }
    if (_hwActive) { _hwActive = NO; [self vkDestroyContext]; }
    _hwRequested = NO; _vkNegotiation = nullptr;
    _input.buttons = 0; _input.latched = 0; _input.polled = 0; _input.touchPressed = false;
}
- (void)stepFrame { if (_gameLoaded) { std::lock_guard<std::mutex> hold(_runLock); _api.run(); } }

/// Runs `block` with the core to itself and waits for it: on the emulation
/// thread between two frames while that thread is alive, directly otherwise.
/// A plain mutex was not enough: a core running behind schedule never sleeps
/// between frames and re-took the (unfair) lock at once, so a save state
/// requested while playing never ran (10-27 test). Never call this from the
/// emulation thread itself.
- (void)performExclusive:(dispatch_block_t)block {
    dispatch_semaphore_t done = nil;
    {
        std::lock_guard<std::mutex> g(_commandLock);
        if (_thread != nil && _shouldRun.load()) {
            dispatch_semaphore_t signal = dispatch_semaphore_create(0);
            done = signal;
            [_commands addObject:[^{ block(); dispatch_semaphore_signal(signal); } copy]];
        }
    }
    if (done) {
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        return;
    }
    std::lock_guard<std::mutex> hold(_runLock);
    block();
}
- (void)drainCommands {
    NSArray<dispatch_block_t> *pending;
    {
        std::lock_guard<std::mutex> g(_commandLock);
        if (_commands.count == 0) return;
        pending = [_commands copy];
        [_commands removeAllObjects];
    }
    std::lock_guard<std::mutex> hold(_runLock);
    for (dispatch_block_t command in pending) { @autoreleasepool { command(); } }
}

#pragma mark - Save states

- (NSData *)saveStateWithError:(NSError **)error {
    if (!_gameLoaded) { if (error) *error = FAError(10, @"no game loaded"); return nil; }
    __block NSData *result = nil;
    __block NSInteger code = 0;
    __block NSString *message = nil;
    [self performExclusive:^{
        size_t size = self->_api.serialize_size();
        if (size == 0) { code = 11; message = @"core reports no state (not powered on, or pending operations did not drain)"; return; }
        NSMutableData *data = [NSMutableData dataWithLength:size];
        if (!self->_api.serialize(data.mutableBytes, size)) { code = 12; message = @"retro_serialize failed"; return; }
        result = data;
    }];
    if (!result && error) *error = FAError(code, message);
    return result;
}

- (BOOL)loadState:(NSData *)data error:(NSError **)error {
    if (!_gameLoaded) { if (error) *error = FAError(10, @"no game loaded"); return NO; }
    if (data.length == 0) { if (error) *error = FAError(13, @"empty state"); return NO; }
    __block BOOL ok = NO;
    [self performExclusive:^{
        ok = self->_api.unserialize(data.bytes, data.length);
        if (ok) { self->_input.buttons = 0; self->_input.latched = 0; self->_input.polled = 0; self->_input.touchPressed = false; }
    }];
    if (!ok && error) *error = FAError(14, @"retro_unserialize failed (state from another game or core version?)");
    return ok;
}

- (void)runLoop {
    @autoreleasepool {
        mach_timebase_info_data_t tb; mach_timebase_info(&tb);
        const double nsPerTick = (double)tb.numer / tb.denom;
        uint64_t frameNs = (uint64_t)(1e9 / _fps);
        uint64_t next = mach_absolute_time();
        // Audio-driven pacing. The core makes audio for emulated time (the 3DS
        // runs at ~59.83 Hz, the core reports 60) and the output drains it at
        // the device's clock, so a fixed 60 Hz timer slowly overfills the ring
        // (measured +0.4 %/s, i.e. latency creeping up to the 2 s ring). While
        // audio is flowing, stretch or shrink each frame by up to a few percent
        // to hold ~50 ms buffered, and never let more than ~150 ms pile up.
        const double audioTarget = _sampleRate * 0.05, audioCeiling = _sampleRate * 0.15;
        uint64_t audioSeen = _audioWritten.load();
        while (_shouldRun.load()) {
            [self drainCommands];
            if (_paused.load()) { [NSThread sleepForTimeInterval:0.01]; next = mach_absolute_time(); continue; }
            const uint64_t runStart = mach_absolute_time();
            @autoreleasepool { std::lock_guard<std::mutex> hold(_runLock); _api.run(); }
            const uint64_t ran = mach_absolute_time() - runStart;
            _runFrames++; _runTicks += ran;
            uint64_t longest = _runMaxTicks.load();
            while (ran > longest && !_runMaxTicks.compare_exchange_weak(longest, ran)) {}
            if (_unthrottled) { next = mach_absolute_time(); continue; }   // benchmark: no pacing
            // 倍速: frames `speed` times as often, by the clock (no sound to pace by).
            const double speed = std::max(1.0, _speed.load());
            const uint64_t written = _audioWritten.load();
            const bool audioFlowing = written != audioSeen && speed <= 1.0;
            audioSeen = written;
            double stretch = 1.0 / speed;
            if (audioFlowing) {
                const double buffered = (double)(_audio.available() / 2);
                stretch = 1.0 + std::clamp((buffered - audioTarget) / audioTarget * 0.03, -0.02, 0.05);
                while (_shouldRun.load() && !_paused.load() && (double)(_audio.available() / 2) > audioCeiling) {
                    [NSThread sleepForTimeInterval:0.002];
                    next = mach_absolute_time();
                }
            }
            next += (uint64_t)((double)frameNs * stretch / nsPerTick);
            uint64_t now = mach_absolute_time();
            if (next > now) {
                mach_wait_until(next);
            } else if (now - next > (uint64_t)(frameNs * 4 / nsPerTick)) {
                next = now;    // far behind: drop the debt instead of spinning
            }
        }
    }
}

#pragma mark - Callbacks

- (bool)environment:(unsigned)cmd data:(void *)data {
    switch (cmd) {
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
        auto *cb = (struct retro_log_callback *)data; cb->log = fa_log; return true; }
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        *(const char **)data = _systemDirectory ? _systemDirectory.fileSystemRepresentation : nullptr; return _systemDirectory != nil;
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        *(const char **)data = _saveDirectory ? _saveDirectory.fileSystemRepresentation : nullptr; return _saveDirectory != nil;
    case RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY:
    case RETRO_ENVIRONMENT_GET_LIBRETRO_PATH:
        return false;
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
        return *(const enum retro_pixel_format *)data == RETRO_PIXEL_FORMAT_XRGB8888;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
        auto *var = (struct retro_variable *)data;
        NSString *value = nil;
        {
            std::lock_guard<std::mutex> lock(_variablesLock);
            value = var->key ? _variables[@(var->key)] : nil;
        }
        var->value = value ? value.UTF8String : nullptr;
        // The 3D slider's two options are read at load and after each change
        // (GET_VARIABLE_UPDATE): log those reads, so a run shows the core
        // took the slider's position.
        if (_echoLogToConsole && var->key && (!strcmp(var->key, "citra_factor_3d") || !strcmp(var->key, "citra_render_3d")))
            NSLog(@"[azahar] core read %s=%@", var->key, value ?: @"(unset)");
        return value != nil;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
        *(bool *)data = _variablesUpdated.exchange(false); return true;
    case RETRO_ENVIRONMENT_GET_MICROPHONE_INTERFACE: {
        auto *mic = (struct retro_microphone_interface *)data;
        if (!mic) return false;
        mic->interface_version = RETRO_MICROPHONE_INTERFACE_VERSION;
        mic->open_mic = fa_open_mic;
        mic->close_mic = fa_close_mic;
        mic->get_params = fa_get_mic_params;
        mic->set_mic_state = fa_set_mic_state;
        mic->get_mic_state = fa_get_mic_state;
        mic->read_mic = fa_read_mic;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
        *(unsigned *)data = 2; return true;
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2: {
        [_options removeAllObjects];
        auto *opts = (const struct retro_core_options_v2 *)data;
        if (opts && opts->definitions) {
            for (auto *d = opts->definitions; d->key; d++) {
                NSMutableString *values = [NSMutableString string];
                for (auto &v : d->values) { if (!v.value) break; if (values.length) [values appendString:@"|"]; [values appendString:@(v.value)]; }
                [_options addObject:@{@"key": @(d->key), @"desc": d->desc ? @(d->desc) : @"", @"default": d->default_value ? @(d->default_value) : @"", @"values": values}];
            }
        }
        return true;
    }
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: {
        auto *intl = (const struct retro_core_options_v2_intl *)data;
        return [self environment:RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2 data:(void *)intl->us];
    }
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL:
    case RETRO_ENVIRONMENT_SET_VARIABLES:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK:
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
    case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
    case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
    case RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS:
    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
    case RETRO_ENVIRONMENT_SET_MINIMUM_AUDIO_LATENCY:
    case RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE:
        return true;
    case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
        auto *av = (const struct retro_system_av_info *)data;
        _fps = av->timing.fps > 0 ? av->timing.fps : _fps;
        _sampleRate = av->timing.sample_rate > 0 ? av->timing.sample_rate : _sampleRate;
        _frameSize = CGSizeMake(av->geometry.base_width, av->geometry.base_height);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_GEOMETRY: {
        auto *g = (const struct retro_game_geometry *)data;
        _frameSize = CGSizeMake(g->base_width, g->base_height);
        return true;
    }
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
        *(bool *)data = true; return true;
    case RETRO_ENVIRONMENT_GET_LANGUAGE:
        *(unsigned *)data = _language; return true;
    case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE:
        *(int *)data = 3; return true;
    case RETRO_ENVIRONMENT_GET_FASTFORWARDING:
        *(bool *)data = false; return true;
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
        return false;
    case RETRO_ENVIRONMENT_GET_INPUT_MAX_USERS:
        *(unsigned *)data = 1; return true;
    case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER:
        // Only consulted when citra_graphics_api is "auto"; FoldArc sets it explicitly.
        if (!_vulkanEnabled) return false;
        *(enum retro_hw_context_type *)data = RETRO_HW_CONTEXT_VULKAN;
        return true;
    case RETRO_ENVIRONMENT_SET_HW_RENDER: {
        auto *hw = (struct retro_hw_render_callback *)data;
        if (!_vulkanEnabled || !hw || hw->context_type != RETRO_HW_CONTEXT_VULKAN) return false;
        hw->get_current_framebuffer = nullptr;   // OpenGL-only fields
        hw->get_proc_address = nullptr;
        _hwRender = *hw;
        _hwRequested = YES;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE: {
        auto *iface = (const struct retro_hw_render_context_negotiation_interface_vulkan *)data;
        if (!_vulkanEnabled || !iface || iface->interface_type != RETRO_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_VULKAN) return false;
        _vkNegotiation = iface;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_SUPPORT: {
        // The host drives the v1 entry points (create_device) only.
        auto *iface = (struct retro_hw_render_context_negotiation_interface *)data;
        if (!iface || iface->interface_type != RETRO_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_VULKAN) return false;
        iface->interface_version = 1;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE:
        if (!_hwActive) return false;
        *(const struct retro_hw_render_interface **)data = (const struct retro_hw_render_interface *)&_vk.iface;
        return true;
    case RETRO_ENVIRONMENT_SET_HW_SHARED_CONTEXT:
        return false;
    case RETRO_ENVIRONMENT_GET_CURRENT_SOFTWARE_FRAMEBUFFER: {
        // Hand the core a fresh buffer each frame; videoRefresh wraps it as a
        // CGImage without copying, and the image keeps the data alive.
        auto *fb = (struct retro_framebuffer *)data;
        size_t pitch = (size_t)fb->width * 4;
        NSMutableData *buffer = [NSMutableData dataWithLength:pitch * fb->height];
        {
            std::lock_guard<std::mutex> lock(_frameLock);
            _pendingFrame = buffer; _pendingPitch = pitch;
        }
        fb->data = buffer.mutableBytes;
        fb->pitch = pitch;
        fb->format = RETRO_PIXEL_FORMAT_XRGB8888;
        fb->memory_flags = 0;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_MESSAGE: {
        auto *m = (const struct retro_message *)data;
        if (m && m->msg) {
            NSString *text = @(m->msg);
            // With a hardware context the game loads inside context_reset, which
            // reports failure only through these messages (do_load_game).
            if (_capturingLoadMessages) {
                for (NSString *needle in @[@"Failed", @"failed", @"must be decrypted", @"not supported", @"not initialized", @"Unknown error", @"Virtual Console"]) {
                    if ([text containsString:needle]) { _loadFailureMessage = text; break; }
                }
            }
            [self.delegate core:self didRequestMessage:text];
        }
        return true;
    }
    case RETRO_ENVIRONMENT_SET_MESSAGE_EXT: {
        auto *m = (const struct retro_message_ext *)data;
        if (m && m->msg) {
            if (m->target == RETRO_MESSAGE_TARGET_LOG) [self log:RETRO_LOG_INFO message:@(m->msg)];
            else [self.delegate core:self didRequestMessage:@(m->msg)];
        }
        return true;
    }
    case RETRO_ENVIRONMENT_GET_MESSAGE_INTERFACE_VERSION:
        *(unsigned *)data = 1; return true;
    case RETRO_ENVIRONMENT_SHUTDOWN:
        _shouldRun = false;
        [self.delegate core:self didStopWithReason:@"core requested shutdown"];
        return true;
    case RETRO_ENVIRONMENT_GET_SENSOR_INTERFACE:
    case RETRO_ENVIRONMENT_GET_CAMERA_INTERFACE:
    case RETRO_ENVIRONMENT_GET_LOCATION_INTERFACE:
    case RETRO_ENVIRONMENT_GET_PERF_INTERFACE:
    case RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE:
    case RETRO_ENVIRONMENT_GET_VFS_INTERFACE:
    case RETRO_ENVIRONMENT_GET_LED_INTERFACE:
    case RETRO_ENVIRONMENT_GET_MIDI_INTERFACE:
    case RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION:
    case RETRO_ENVIRONMENT_GET_THROTTLE_STATE:
    case RETRO_ENVIRONMENT_GET_SAVESTATE_CONTEXT:
    case RETRO_ENVIRONMENT_GET_JIT_CAPABLE:
        return false;
    default:
        return false;
    }
}

- (void)videoRefresh:(const void *)data width:(unsigned)w height:(unsigned)h pitch:(size_t)pitch {
    if (!data || w == 0 || h == 0) return;    // duplicate frame
    if (data == RETRO_HW_FRAME_BUFFER_VALID) {
        if (_hwActive) [self vkReadBackFrameWidth:w height:h];   // presents once the copy is done
        return;
    }
    NSData *backing = nil;
    {
        std::lock_guard<std::mutex> lock(_frameLock);
        if (_pendingFrame && _pendingFrame.mutableBytes == data) { backing = _pendingFrame; _pendingFrame = nil; }
    }
    if (!backing) {
        // The core used its own buffer (freed right after this call): copy.
        backing = [NSData dataWithBytes:data length:pitch * h];
    }
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)backing);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo info = (CGBitmapInfo)kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaNoneSkipFirst;   // XRGB8888 LE = B,G,R,X
    CGImageRef frame = CGImageCreate(w, h, 8, 32, pitch, space, info, provider, nullptr, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    if (!frame) return;
    [self presentFrame:frame width:w height:h];
    CGImageRelease(frame);
}

/// Splits a composed frame into the two screens and hands them to the delegate.
- (void)presentFrame:(CGImageRef)frame width:(unsigned)w height:(unsigned)h {
    // Default layout: top 400x240 at (0,0), bottom 320x240 centred below, all × resolution factor.
    double scale = (double)w / 400.0;
    CGRect topRect = CGRectMake(0, 0, 400 * scale, 240 * scale);
    CGRect bottomRect = CGRectMake(40 * scale, 240 * scale, 320 * scale, 240 * scale);
    CGImageRef top = nullptr, bottom = nullptr;
    if (h >= 480 * scale - 1) {
        top = CGImageCreateWithImageInRect(frame, topRect);
        bottom = CGImageCreateWithImageInRect(frame, bottomRect);
    } else {
        top = CGImageRetain(frame);
    }
    _presented++;
    [self.delegate core:self didPresentTop:top bottom:bottom];
    if (top) CGImageRelease(top);
    if (bottom) CGImageRelease(bottom);
}

- (size_t)audioBatch:(const int16_t *)data frames:(size_t)frames {
    // 倍速: the sound is dropped (counted, not played).
    if (_speed.load() <= 1.0) _audio.write(data, frames * 2);
    _audioIn += frames;
    _audioWritten += frames;
    return frames;
}

- (NSUInteger)readAudioInto:(int16_t *)buffer frames:(NSUInteger)frames {
    // Audio render thread: lock-free counters only.
    const size_t samples = _audio.read(buffer, frames * 2);
    uint64_t squares = 0;
    uint32_t peak = 0;
    for (size_t i = 0; i < samples; i++) {
        const int32_t v = buffer[i];
        squares += (uint64_t)(v * v);
        const uint32_t a = (uint32_t)(v < 0 ? -v : v);
        if (a > peak) peak = a;
    }
    _audioOut += samples / 2;
    _audioUnderrun += frames - samples / 2;
    _audioSquares += squares;
    uint32_t seen = _audioPeak.load();
    while (peak > seen && !_audioPeak.compare_exchange_weak(seen, peak)) {}
    return samples / 2;
}

- (FAAudioStats)takeAudioStats {
    FAAudioStats stats;
    stats.framesIn = _audioIn.exchange(0);
    stats.framesOut = _audioOut.exchange(0);
    stats.underrunFrames = _audioUnderrun.exchange(0);
    const uint64_t squares = _audioSquares.exchange(0);
    stats.peak = (double)_audioPeak.exchange(0);
    stats.rms = stats.framesOut > 0 ? sqrt((double)squares / (double)(stats.framesOut * 2)) : 0;
    stats.buffered = _audio.available() / 2;
    return stats;
}

- (FAFrameStats)takeFrameStats {
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    const double msPerTick = (double)tb.numer / tb.denom / 1e6;
    FAFrameStats stats = {};
    stats.frames = _runFrames.exchange(0);
    const uint64_t run = _runTicks.exchange(0);
    stats.runAverage = stats.frames ? (double)run * msPerTick / (double)stats.frames : 0;
    stats.runMax = (double)_runMaxTicks.exchange(0) * msPerTick;
    stats.readbacks = _vk.readbacks.exchange(0);
    const uint64_t wait = _vk.readbackWaitTicks.exchange(0);
    stats.readbackWaitAverage = stats.readbacks ? (double)wait * msPerTick / (double)stats.readbacks : 0;
    stats.readbackWaitMax = (double)_vk.readbackWaitMax.exchange(0) * msPerTick;
    stats.syncIndexWait = (double)_vk.syncWaitTicks.exchange(0) * msPerTick;
    stats.slotWait = (double)_vk.slotWaitTicks.exchange(0) * msPerTick;
    return stats;
}

- (int16_t)inputStatePort:(unsigned)port device:(unsigned)device index:(unsigned)index id:(unsigned)id {
    if (port != 0) return 0;
    switch (device) {
    case RETRO_DEVICE_JOYPAD:
        return (_input.polled.load() >> id) & 1;
    case RETRO_DEVICE_ANALOG:
        if (index == RETRO_DEVICE_INDEX_ANALOG_LEFT) return id == RETRO_DEVICE_ID_ANALOG_X ? _input.padX.load() : _input.padY.load();
        if (index == RETRO_DEVICE_INDEX_ANALOG_RIGHT) return id == RETRO_DEVICE_ID_ANALOG_X ? _input.cstickX.load() : _input.cstickY.load();
        return 0;
    case RETRO_DEVICE_POINTER:
        if (id == RETRO_DEVICE_ID_POINTER_PRESSED) return _input.touchPressed.load() ? 1 : 0;
        if (id == RETRO_DEVICE_ID_POINTER_X) return _input.touchX.load();
        if (id == RETRO_DEVICE_ID_POINTER_Y) return _input.touchY.load();
        if (id == RETRO_DEVICE_ID_POINTER_COUNT) return _input.touchPressed.load() ? 1 : 0;
        return 0;
    default:
        return 0;
    }
}

- (void)log:(enum retro_log_level)level message:(NSString *)message {
    NSString *line = [message stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
    // The delegate hops to the main thread; when the main thread is the one
    // loading the game and the process dies there, those lines never print.
    if (_echoLogToConsole && level >= RETRO_LOG_INFO) NSLog(@"[azahar] core: %@", line);
    [self.delegate core:self didLog:line level:level];
}

#pragma mark - Input from the UI

static int16_t clampAxis(float v) { v = fmaxf(-1, fminf(1, v)); return (int16_t)lrintf(v * 32767.0f); }

- (void)setButton:(FACoreButton)button pressed:(BOOL)pressed {
    uint32_t mask = 1u << button;
    if (pressed) { _input.buttons.fetch_or(mask); _input.latched.fetch_or(mask); }
    else _input.buttons.fetch_and(~mask);
}
/// Once per frame, on the emulation thread: what is held now, plus anything
/// pressed and already released since the previous frame.
- (void)pollInput {
    _input.polled = _input.buttons.load() | _input.latched.exchange(0);
}

#pragma mark - Options and microphone while running

- (NSDictionary<NSString *, NSString *> *)variables {
    std::lock_guard<std::mutex> lock(_variablesLock);
    return _variables;
}
- (void)setVariables:(NSDictionary<NSString *, NSString *> *)variables {
    std::lock_guard<std::mutex> lock(_variablesLock);
    _retiredVariables = _variables;
    _variables = [variables copy] ?: @{};
}
- (void)setVariable:(NSString *)key value:(NSString *)value {
    {
        std::lock_guard<std::mutex> lock(_variablesLock);
        if ([_variables[key] isEqualToString:value]) return;
        NSMutableDictionary *next = [_variables mutableCopy] ?: [NSMutableDictionary dictionary];
        next[key] = value;
        _retiredVariables = _variables;
        _variables = [next copy];
    }
    _variablesUpdated = true;
}

- (BOOL)micBlowing { return _micBlowingFlag.load(); }
- (void)setMicBlowing:(BOOL)micBlowing { _micBlowingFlag = micBlowing; }
- (void)micOpenedAtRate:(unsigned)rate {
    _micActive = false; _micLastRead = 0; _micOwed = 0;
    if (_echoLogToConsole) NSLog(@"[azahar] mic: opened (asked for %u Hz, given 48000 Hz)", rate);
}
- (void)micClosed {
    _micActive = false;
    if (_echoLogToConsole) NSLog(@"[azahar] mic: closed");
}
- (void)setMicActive:(bool)active {
    if (_micActive.exchange(active) != active && _echoLogToConsole) NSLog(@"[azahar] mic: %@", active ? @"listening" : @"idle");
    _micLastRead = 0; _micOwed = 0;
}
- (bool)micActive { return _micActive.load(); }
- (BOOL)micListening { return _micActive.load() ? YES : NO; }
/// The core asks every frame (on the emulation thread), in reads of 128
/// samples until one comes back short (Azahar patch 0007). Hand over what
/// 48 kHz produced since the previous frame: silence, or while MIC is held, a
/// breath (low-passed noise with a quick swell, loud enough for games that
/// listen for blowing). Never blocks. At most 2048 samples are owed, so after
/// a pause the stream does not catch up on the time it stood still.
- (int)readMic:(int16_t *)samples count:(size_t)count {
    if (!_micActive.load() || !samples || count == 0) return 0;
    const uint64_t now = mach_absolute_time();
    if (_micLastRead) {
        mach_timebase_info_data_t tb; mach_timebase_info(&tb);
        const double seconds = (double)(now - _micLastRead) * tb.numer / tb.denom / 1e9;
        _micOwed = std::min(2048.0, _micOwed + std::max(0.0, seconds * 48000.0));
    } else {
        _micOwed = (double)count;
    }
    _micLastRead = now;
    const size_t due = (size_t)std::min((double)count, std::floor(_micOwed));
    _micOwed -= (double)due;
    const bool blowing = _micBlowingFlag.load();
    if (_noiseState == 0) _noiseState = 0x9E3779B9u;
    for (size_t i = 0; i < due; i++) {
        // xorshift32 white noise -> one-pole low-pass (breath), envelope.
        _noiseState ^= _noiseState << 13; _noiseState ^= _noiseState >> 17; _noiseState ^= _noiseState << 5;
        const float white = (float)((int32_t)_noiseState) / 2147483648.0f;
        _noiseLow += 0.18f * (white - _noiseLow);
        _noiseEnvelope += ((blowing ? 1.0f : 0.0f) - _noiseEnvelope) * (blowing ? 0.004f : 0.01f);
        const float v = std::max(-1.0f, std::min(1.0f, _noiseLow * 2.2f * _noiseEnvelope));
        samples[i] = (int16_t)lrintf(v * 26000.0f);
    }
    return (int)due;
}
- (void)setCirclePadX:(float)x y:(float)y { _input.padX = clampAxis(x); _input.padY = clampAxis(y); }
- (void)setCStickX:(float)x y:(float)y { _input.cstickX = clampAxis(x); _input.cstickY = clampAxis(y); }
- (void)setTouchX:(float)x y:(float)y pressed:(BOOL)pressed {
    // libretro pointer coordinates span the whole frame (-0x7fff...0x7fff);
    // map the bottom-screen rectangle of the default layout into that range.
    double fx = (40.0 + fmax(0, fmin(1, x)) * 320.0) / 400.0;   // 0..1 across the frame
    double fy = (240.0 + fmax(0, fmin(1, y)) * 240.0) / 480.0;
    _input.touchX = (int16_t)lrint((fx * 2 - 1) * 32767);
    _input.touchY = (int16_t)lrint((fy * 2 - 1) * 32767);
    _input.touchPressed = pressed;
}

@end

// MARK: - Compressed game files

namespace {
struct Z3DSReader {
    void *(*open)(const char *) = nullptr;
    uint64_t (*size)(void *) = nullptr;
    void (*magic)(void *, uint8_t *) = nullptr;
    uint64_t (*read)(void *, uint64_t, void *, uint64_t) = nullptr;
    void (*close)(void *) = nullptr;
    int (*compress)(const char *, const char *, const uint8_t *) = nullptr;
    bool complete() const { return open && size && read && close; }
};
/// The reader's functions from the core at `path` (the same library the
/// host runs: loading it again gives the one already there).
const Z3DSReader &Z3DSReaderOfCore(NSString *path) {
    static Z3DSReader reader;
    static std::once_flag once;
    std::call_once(once, [path] {
        void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (!handle) { NSLog(@"[core] compressed files: the core did not load (%s)", dlerror() ?: "?"); return; }
        *(void **)&reader.open = dlsym(handle, "zeroemu_z3ds_open");
        *(void **)&reader.size = dlsym(handle, "zeroemu_z3ds_size");
        *(void **)&reader.magic = dlsym(handle, "zeroemu_z3ds_magic");
        *(void **)&reader.read = dlsym(handle, "zeroemu_z3ds_read");
        *(void **)&reader.close = dlsym(handle, "zeroemu_z3ds_close");
        *(void **)&reader.compress = dlsym(handle, "zeroemu_z3ds_compress");
        NSLog(@"[core] compressed files: the core's reader is %s", reader.complete() ? "there" : "not in this core");
    });
    return reader;
}
}

@implementation FACompressedGameFile {
    void *_file;
    const Z3DSReader *_reader;
    std::mutex _lock;
}

+ (instancetype)openPath:(NSString *)path corePath:(NSString *)corePath {
    const Z3DSReader &reader = Z3DSReaderOfCore(corePath);
    if (!reader.complete()) return nil;
    void *file = reader.open(path.fileSystemRepresentation);
    if (!file) return nil;
    FACompressedGameFile *opened = [[FACompressedGameFile alloc] init];
    opened->_file = file;
    opened->_reader = &reader;
    return opened;
}

- (uint64_t)size {
    std::lock_guard<std::mutex> hold(_lock);
    return _file ? _reader->size(_file) : 0;
}

- (NSData *)readAtOffset:(uint64_t)offset count:(NSUInteger)count {
    std::lock_guard<std::mutex> hold(_lock);
    if (!_file || count == 0) return [NSData data];
    uint64_t size = _reader->size(_file);
    if (offset >= size) return [NSData data];
    NSUInteger wanted = (NSUInteger)std::min<uint64_t>(count, size - offset);
    NSMutableData *data = [NSMutableData dataWithLength:wanted];
    uint64_t got = _reader->read(_file, offset, data.mutableBytes, wanted);
    if (got > wanted) got = 0;
    data.length = (NSUInteger)got;
    return data;
}

- (void)close {
    std::lock_guard<std::mutex> hold(_lock);
    if (_file) { _reader->close(_file); _file = nullptr; }
}

- (void)dealloc { [self close]; }

+ (BOOL)compressPath:(NSString *)source to:(NSString *)destination magic:(NSData *)magic corePath:(NSString *)corePath {
    const Z3DSReader &reader = Z3DSReaderOfCore(corePath);
    if (!reader.compress || magic.length < 4) return NO;
    return reader.compress(source.fileSystemRepresentation, destination.fileSystemRepresentation, (const uint8_t *)magic.bytes) == 1;
}

@end

