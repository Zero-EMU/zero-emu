// FoldArc · libretro core host (Objective-C++ side).
// Loads a libretro core (Azahar's azahar_libretro.dylib) with dlopen, drives
// retro_run on a dedicated thread, and hands the software-rendered frame,
// audio and messages back to Swift. No emulator code lives here; the core is
// GPL software built from source by Scripts/build-azahar-ios.sh.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// libretro joypad ids (RETRO_DEVICE_ID_JOYPAD_*), re-exported so Swift
/// does not need libretro.h.
typedef NS_ENUM(NSUInteger, FACoreButton) {
    FACoreButtonB = 0, FACoreButtonY = 1, FACoreButtonSelect = 2, FACoreButtonStart = 3,
    FACoreButtonUp = 4, FACoreButtonDown = 5, FACoreButtonLeft = 6, FACoreButtonRight = 7,
    FACoreButtonA = 8, FACoreButtonX = 9, FACoreButtonL = 10, FACoreButtonR = 11,
    FACoreButtonZL = 12, FACoreButtonZR = 13,
};

/// Audio counters since the previous takeAudioStats (stereo frames; peak and
/// RMS are of the int16 samples handed to the output).
typedef struct {
    uint64_t framesIn;        ///< delivered by the core
    uint64_t framesOut;       ///< read by the audio output
    uint64_t underrunFrames;  ///< asked for by the output but not available (played as silence)
    uint64_t buffered;        ///< waiting in the ring right now
    double peak;
    double rms;
} FAAudioStats;

/// Emulation-thread timing since the previous takeFrameStats, in milliseconds
/// (diagnostics for the Vulkan read-back).
typedef struct {
    uint64_t frames;                ///< retro_run calls on the emulation thread
    double runAverage, runMax;      ///< wall time of one retro_run (includes a synchronous read-back)
    uint64_t readbacks;             ///< Vulkan frames copied back
    double readbackWaitAverage, readbackWaitMax;   ///< waiting for each copy's fence
    double syncIndexWait;           ///< total the core waited in wait_sync_index for pending copies
    double slotWait;                ///< total video_refresh waited for a free read-back slot
} FAFrameStats;

@class FALibretroCore;

@protocol FALibretroCoreDelegate <NSObject>
/// Called on the emulation thread (software renderer) or on the Vulkan
/// read-back queue, never concurrently. `top` is 400x240, `bottom` 320x240 (at
/// resolution factor 1); both share the frame's backing store.
- (void)core:(FALibretroCore *)core didPresentTop:(nullable CGImageRef)top bottom:(nullable CGImageRef)bottom;
/// Core log lines (already formatted), emulation thread.
- (void)core:(FALibretroCore *)core didLog:(NSString *)line level:(NSInteger)level;
/// On-screen messages the core asks the frontend to show.
- (void)core:(FALibretroCore *)core didRequestMessage:(NSString *)message;
/// The run loop stopped on its own (core error).
- (void)core:(FALibretroCore *)core didStopWithReason:(NSString *)reason;
@end

@interface FALibretroCore : NSObject

@property (class, readonly, strong) FALibretroCore *shared;

@property (nonatomic, weak, nullable) id<FALibretroCoreDelegate> delegate;
/// Core options answered to RETRO_ENVIRONMENT_GET_VARIABLE. Set before loadGame.
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *variables;
/// Changes one core option while a game runs; the core picks it up before its
/// next frame (RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE). Any thread.
- (void)setVariable:(NSString *)key value:(NSString *)value NS_SWIFT_NAME(setVariable(_:value:));
/// The MIC hole is held: the microphone the core opens (RETRO_ENVIRONMENT_
/// GET_MICROPHONE_INTERFACE) hears a breath, otherwise silence. FoldArc does
/// not record from the iPhone's microphone.
@property (atomic) BOOL micBlowing;
/// 11-06: the software has its microphone open and is sampling it
/// (the iPhone's own microphone is on meanwhile). Any thread.
@property (atomic, readonly) BOOL micListening;
/// Option definitions the core published (key -> human description), after loadCore.
@property (nonatomic, readonly) NSArray<NSDictionary<NSString *, NSString *> *> *publishedOptions;
@property (nonatomic, readonly) BOOL coreLoaded;
@property (nonatomic, readonly) BOOL gameLoaded;
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) double fps;
@property (nonatomic, readonly) double sampleRate;
@property (nonatomic, readonly) CGSize frameSize;
@property (nonatomic, readonly) NSString *coreName;
@property (nonatomic, readonly) NSString *coreVersion;
/// Frames presented since loadGame; useful for tests and the HUD.
@property (nonatomic, readonly) uint64_t presentedFrames;

/// Also NSLog every core log line (INFO and above) synchronously, on the
/// calling thread (diagnostics; the delegate gets them on main later).
@property (nonatomic) BOOL echoLogToConsole;
/// Allow a Vulkan context (MoltenVK) for the next loadGame. The core only
/// asks for one when its `citra_graphics_api` option is "Vulkan"; the two must
/// agree, or retro_load_game fails.
@property (nonatomic) BOOL vulkanEnabled;
/// Finish each Vulkan read-back (fence wait, pixel copy, present) on a serial
/// queue so the emulation thread only submits the copy (default). NO waits
/// inside video_refresh, as before 10-27 (diagnostics). Read at loadGame.
@property (nonatomic) BOOL vulkanAsyncReadback;
/// Run frames back to back without pacing (DEBUG throughput benchmarks; the
/// audio ring overflows and the excess is dropped).
@property (nonatomic) BOOL unthrottled;
/// 倍速 (11-07): frames run this many times as often (1, 2, 4), paced by the
/// clock alone; above 1 the sound is dropped (it would pile up or play high).
@property (atomic) double speed;
/// "Vulkan · <GPU>" while the loaded game renders through Vulkan, nil for the software renderer.
@property (nonatomic, readonly, nullable) NSString *hardwareRenderer;
/// Loads MoltenVK from the app's Frameworks and checks it exposes a Vulkan
/// device; returns the device name, or nil with the reason.
- (nullable NSString *)probeVulkanWithError:(NSError **)error NS_SWIFT_NAME(probeVulkan());

- (BOOL)loadCoreAtPath:(NSString *)path error:(NSError **)error NS_SWIFT_NAME(loadCore(path:));
- (BOOL)loadGameAtPath:(NSString *)path
       systemDirectory:(NSString *)systemDirectory
         saveDirectory:(NSString *)saveDirectory
                 error:(NSError **)error NS_SWIFT_NAME(loadGame(path:systemDirectory:saveDirectory:));
/// Runs the emulation thread; `pause` holds it between frames.
- (void)start;
/// Starts the emulation thread already paused: it runs no frame, but queued
/// commands (save states) are carried out. `resume` lets it run.
- (void)startPaused;
- (void)pause;
- (void)resume;
/// Stops the thread and unloads the game. The core stays loaded.
- (void)stop;
/// Runs exactly one frame synchronously (tests, stepping).
- (void)stepFrame;

/// Serializes the whole emulation state (retro_serialize). Safe to call from
/// any thread while running: it waits for the current frame to finish, so
/// expect up to one frame of latency plus the core's own drain (Azahar waits
/// for pending async operations, up to 5 s in pathological cases).
- (nullable NSData *)saveStateWithError:(NSError **)error NS_SWIFT_NAME(saveState());
/// Restores a state produced by saveState for the same game and core build.
- (BOOL)loadState:(NSData *)data error:(NSError **)error NS_SWIFT_NAME(loadState(_:));

- (void)setButton:(FACoreButton)button pressed:(BOOL)pressed;
/// Circle Pad / C-Stick, each axis -1...1.
- (void)setCirclePadX:(float)x y:(float)y;
- (void)setCStickX:(float)x y:(float)y;
/// Touch on the bottom screen, normalized 0...1 within that screen.
- (void)setTouchX:(float)x y:(float)y pressed:(BOOL)pressed;

/// Audio: copies up to `frames` stereo int16 frames into `buffer`; returns how many were available.
- (NSUInteger)readAudioInto:(int16_t *)buffer frames:(NSUInteger)frames;
/// Returns and resets the audio counters (any thread).
- (FAAudioStats)takeAudioStats;
/// Returns and resets the frame timing counters (any thread).
- (FAFrameStats)takeFrameStats;

@end

/// A compressed game file (Z3DS: .zcci, .zcxi, .z3dsx) read as what is
/// inside it, through the core's own reader (six small functions the core
/// exports beside libretro's, Scripts/patches/azahar/0008). The library
/// uses it to look into a file it is given; a game is run by the core alone.
@interface FACompressedGameFile : NSObject
/// nil: not a Z3DS file, or this core has no reader.
+ (nullable instancetype)openPath:(NSString *)path corePath:(NSString *)corePath NS_SWIFT_NAME(open(path:corePath:));
/// The size of what is inside, decompressed.
@property (nonatomic, readonly) uint64_t size;
/// Up to `count` decompressed bytes from `offset` (fewer at the end).
- (NSData *)readAtOffset:(uint64_t)offset count:(NSUInteger)count NS_SWIFT_NAME(read(offset:count:));
- (void)close;
/// Compresses `source` into `destination` (the tests make their compressed
/// files with it). `magic`: the four bytes that say what the file is.
+ (BOOL)compressPath:(NSString *)source to:(NSString *)destination magic:(NSData *)magic corePath:(NSString *)corePath NS_SWIFT_NAME(compress(path:to:magic:corePath:));
@end

NS_ASSUME_NONNULL_END
