// SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

import ARKit
import AVFoundation
import CoreImage
import ImageIO
import Metal
import MetalPerformanceShaders

/// VIDEO and DEPTH: the camera's picture and its depth as two NDI® sources on the local network (NDI® is a registered trademark
/// of Vizrt NDI AB; ndi.video). The cameras (Face's ARKit, Hand's capture) hand their frames here, and each goes out stood up as
/// the phone is held, with its metadata (Frames.meta: the frame, the clock, the lens, where the camera is):
/// - VIDEO: 8-bit UYVY in the standard and range NDI reads for its size (the GPU: shader), its short side 1080 or 720; with
///   MATTE the people in an alpha plane (UYVA, from ARKit); with AUDIO the mic.
/// - DEPTH: 16-bit P216, the distance in the brightness, near white, by 1/distance (Frames.depthCode) or by histogram (EQ), at
///   VIDEO's size, pixel for pixel, its edges on the picture's (sharpen: the guided filter on the GPU); its range FAR's metres,
///   AUTO the scene's or FACE the nearest thing's (range).
/// Nothing is worked on while no one watches (NDI counts the receivers). Quality first: warm (serious) keeps everything, only
/// critical pauses it until it cools (iOS would stop the camera). NDI's SDK comes with the build (ci_scripts/ci_post_clone.sh fetches it from NDI); a build without it
/// (NDI not set) still reads the cameras for the cards, and the page says NOT IN THIS BUILD.
final class NDI {
    struct Settings: Equatable {
        var video = false, depth = false     // the cards on (and the camera allowed, SensorLove on the screen)
        var name = "SENSORLOVE"               // the sources are NAME VIDEO and NAME DEPTH
        var hd = true, max = true             // VIDEO's short side: MAX the camera's own (1440 with DEPTH, 4K without), else 1080 (hd) or 720
        var matte = false, audio = false      // VIDEO: the people in its alpha; the mic with it
        var far: Float = 5, auto = true       // DEPTH: metres where it fades to black, or AUTO the scene's
        var face = false, eq = false          // DEPTH: with auto, FACE: a window on the nearest thing; EQ: the greys by histogram
        var smooth = true                     // DEPTH: iOS's own filter (TrueDepth, LiDAR) or, on ARKit's LiDAR, steadied here; off: each frame as measured
        var detail = false                    // DEPTH: DETAIL AI, the network's edges and folds tied to the sensor (Detail, sharpen); off: SENSOR
        var hz = 30                           // the page's CAMERA rate
    }

    /// A camera's frame for VIDEO: its stored picture (Y'CbCr 4:2:0, two planes) and how it stands up, its lens (in px's pixels),
    /// where the camera is (ARKit's world tracking), and ARKit's frame for MATTE
    struct Picture { let px: CVPixelBuffer; let t: Double; let look: Frames.Look; let k: simd_float3x3?; let pose: simd_float4x4?; let ar: ARFrame? }

    /// A depth frame for DEPTH: metres (DepthFloat32), and how sure ARKit is of each (0 low, 1 medium, 2 high) when it says; guide:
    /// the camera's picture of the same moment (lined up with the depth): DEPTH is made its size along its edges (sharpen);
    /// steady: steadied over time here (Frames.Clean): ARKit's LiDAR depth, which no one smoothed, with SMOOTH on
    struct Depth { let px: CVPixelBuffer; let sure: CVPixelBuffer?; var guide: CVPixelBuffer? = nil; let t: Double; let look: Frames.Look; let k: simd_float3x3?; let pose: simd_float4x4?; var steady = false }

    var told: ([String: Any]) -> Void = { _ in }                      // the sources' state for the page, when it changes; on the NDI queue
    var thumb: (String, Data) -> Void = { _, _ in }                   // each source's picture as sent, small (a JPEG), for its card: 15 a second
    var said: (String) -> Void = { _ in }                             // a problem, for the console

    #if NDI
    static let built = true
    #else
    static let built = false
    #endif

    private struct Job { var w, h, turns, mirror: UInt32; var y, cb, cr: SIMD4<Float>; var alpha: UInt32 }   // the shader's Job, field for field

    /// VIDEO's frame on the GPU: the camera's stored picture (its Y and CbCr planes) stood up, scaled to the size sent and turned into
    /// NDI's 8-bit UYVY, in the standard and range NDI reads for that size (Frames.convert); with MATTE, the people after it as an alpha
    /// plane (UYVA). Compiled on the phone, once: Xcode Cloud's Xcode 26 has no Metal toolchain to build a .metal file ahead
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    /// VIDEO's frame on the GPU (NDI.swift): the camera's stored picture (its Y and CbCr planes) stood up, scaled to the size sent and
    /// turned into NDI's 8-bit UYVY, in the standard and range NDI reads for that size (Frames.convert); with MATTE, the people after
    /// it as an alpha plane (UYVA). Field for field what NDI.Job is in Swift.
    struct Job {
        uint w, h;            // the picture sent, stood up
        uint turns, mirror;   // Frames.Look: quarter turns clockwise, then left and right swapped
        float4 y, cb, cr;     // Frames.convert: (y, cb, cr, 1) as read (0 to 1) to NDI's codes
        uint alpha;           // 1: the people's alpha plane after the UYVY one
    };

    // where a point of the picture sent (0 to w, 0 to h) is in the stored one, 0 to 1 (Frames.place, the other way)
    static float2 stored(float2 q, uint w, uint h, uint turns, uint mirror) {
        float wo = w, ho = h, ws = (turns & 1) ? ho : wo, hs = (turns & 1) ? wo : ho;
        if (mirror) { q.x = wo - q.x; }
        float2 p = q;
        switch (turns & 3) {
            case 1: p = float2(q.y, hs - q.x); break;
            case 2: p = float2(ws - q.x, hs - q.y); break;
            case 3: p = float2(ws - q.y, q.x); break;
            default: break;
        }
        return p / float2(ws, hs);
    }

    static uchar code(float v) { return uchar(clamp(round(v), 1.0f, 254.0f)); }   // 0 and 255 are SDI's: kept out

    // one thread a pair of pixels: UYVY carries one Cb and one Cr for two
    kernel void video(texture2d<float, access::sample> luma [[texture(0)]],
                      texture2d<float, access::sample> chroma [[texture(1)]],
                      texture2d<float, access::sample> people [[texture(2)]],
                      device uchar *out [[buffer(0)]],
                      constant Job &j [[buffer(1)]],
                      uint2 g [[thread_position_in_grid]]) {
        if (g.x * 2 >= j.w || g.y >= j.h) { return; }
        constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
        float2 a = stored(float2(g.x * 2 + 0.5f, g.y + 0.5f), j.w, j.h, j.turns, j.mirror), b = stored(float2(g.x * 2 + 1.5f, g.y + 0.5f), j.w, j.h, j.turns, j.mirror);
        float4 va = float4(luma.sample(s, a).r, chroma.sample(s, a).rg, 1), vb = float4(luma.sample(s, b).r, chroma.sample(s, b).rg, 1);
        uint i = (g.y * j.w + g.x * 2) * 2;
        out[i] = code((dot(j.cb, va) + dot(j.cb, vb)) * 0.5f);
        out[i + 1] = code(dot(j.y, va));
        out[i + 2] = code((dot(j.cr, va) + dot(j.cr, vb)) * 0.5f);
        out[i + 3] = code(dot(j.y, vb));
        if (j.alpha) {   // straight alpha, full range (NDI's rule for alpha)
            uint k = j.w * j.h * 2 + g.y * j.w + g.x * 2;
            out[k] = uchar(round(saturate(people.sample(s, a).r) * 255));
            out[k + 1] = uchar(round(saturate(people.sample(s, b).r) * 255));
        }
    }
    """

    private struct LowJob { var w, h: UInt32; var sx, sy: Float; var conf: UInt32 }               // deepShader's Low, field for field
    private struct DeepJob { var w, h, turns, mirror, eq: UInt32; var near, far: Float }           // its Deep
    private struct FitJob { var w, h: UInt32; var s, t: Float; var r: UInt32 }                    // its Fit

    /// DEPTH's two passes on the GPU (sharpen), compiled after VIDEO's shader (its stored()) into a library of their own: a problem
    /// here leaves VIDEO alone, and DEPTH goes the CPU's way
    private static let deepShader = """

    struct Low {          // the depth camera's grid
        uint w, h;        // its size
        float sx, sy;     // the picture's pixels to one of its, each way
        uint conf;        // 1: ARKit's confidence (0 low, 1 medium, 2 high) in texture 3
    };

    // the depth camera's grid: 1/distance (0 none), the guided filter's weight (how sure), measured or not, and the picture's Y, Cb, Cr
    // averaged over the pixels it covers (the guide the regression reads)
    kernel void low(texture2d<float, access::read> metres [[texture(0)]],
                    texture2d<float, access::read> luma [[texture(1)]],
                    texture2d<float, access::read> chroma [[texture(2)]],
                    texture2d<float, access::read> sure [[texture(3)]],
                    texture2d<float, access::write> inv [[texture(4)]],
                    texture2d<float, access::write> weight [[texture(5)]],
                    texture2d<float, access::write> has [[texture(6)]],
                    texture2d<float, access::write> guide [[texture(7)]],
                    constant Low &j [[buffer(0)]],
                    uint2 g [[thread_position_in_grid]]) {
        if (g.x >= j.w || g.y >= j.h) { return; }
        float m = metres.read(g).r;
        bool ok = isfinite(m) && m > 0.0f;
        float c = j.conf ? round(sure.read(g).r * 255.0f) : 2.0f;
        inv.write(float4(ok ? 1.0f / m : 0.0f), g);
        weight.write(float4(!ok ? 0.0f : c >= 2.0f ? 1.0f : c >= 1.0f ? 0.5f : 0.1f), g);
        has.write(float4(ok ? 1.0f : 0.0f), g);
        uint x0 = uint(float(g.x) * j.sx), y0 = uint(float(g.y) * j.sy);
        uint x1 = max(x0 + 1, min(uint(float(g.x + 1) * j.sx), luma.get_width())), y1 = max(y0 + 1, min(uint(float(g.y + 1) * j.sy), luma.get_height()));
        float3 s = float3(0.0f);
        for (uint y = y0; y < y1; y++) {
            for (uint x = x0; x < x1; x++) { s += float3(luma.read(uint2(x, y)).r, chroma.read(uint2(x / 2, y / 2)).rg); }
        }
        guide.write(float4(s / float((x1 - x0) * (y1 - y0)), 1.0f), g);
    }

    struct Deep {         // DEPTH sent
        uint w, h;        // its size, stood up
        uint turns, mirror;
        uint eq;          // 1: EQ's 33 distances in q, else 1/distance between near and far
        float zNear, zFar;
    };

    // a 1/distance's code (Frames.depthCode, Frames.eqCodes): near white, 4096 none or beyond far, never under 32 in range
    static ushort deepCode(float z, constant Deep &j, constant float *q) {
        if (!(z > 0.0f) || !isfinite(z)) { return 4096; }
        float v;
        if (j.eq) {
            float m = 1.0f / z;
            if (m > q[32]) { return 4096; }
            if (m <= q[0]) { v = 1.0f; }
            else {
                uint k = 0;
                while (k < 31 && m > q[k + 1]) { k++; }
                float d = q[k + 1] - q[k], f = d > 0.0f ? clamp((m - q[k]) / d, 0.0f, 1.0f) : 0.0f;
                v = 1.0f - (float(k) + f) / 32.0f;
            }
        } else {
            float a = 1.0f / j.zFar, b = 1.0f / j.zNear;
            if (z < a) { return 4096; }
            v = min((z - a) / (b - a), 1.0f);
        }
        return ushort(4096.0f + clamp(round(v * 56064.0f), 32.0f, 56064.0f));
    }

    // a texture read between its pixels by hand (p: 0 to 1, as a sampler's linear, clamped at the edges): 32-bit floats are not
    // filtered on every GPU, and the coefficients want all their bits
    static float4 bilinear(texture2d<float, access::read> t, float2 p) {
        int2 size = int2(t.get_width(), t.get_height()), i = int2(floor(p * float2(size) - 0.5f));
        float2 f = fract(p * float2(size) - 0.5f);
        float4 a = t.read(uint2(clamp(i, int2(0), size - 1))), b = t.read(uint2(clamp(i + int2(1, 0), int2(0), size - 1)));
        float4 c = t.read(uint2(clamp(i + int2(0, 1), int2(0), size - 1))), d = t.read(uint2(clamp(i + int2(1, 1), int2(0), size - 1)));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    struct Fit {          // DETAIL: a grid's size, the network's line to the sensor's 1/distance (Frames.fit), the blur's radius
        uint w, h;
        float s, t;
        uint r;
    };

    // DETAIL, on the sensor's grid: how far its 1/distance is from the network's line there (weight 1; none: 0), to be smoothed
    kernel void resid(texture2d<float, access::read> metres [[texture(0)]],
                      texture2d<float, access::read> net [[texture(1)]],
                      texture2d<float, access::write> out [[texture(2)]],
                      constant Fit &j [[buffer(0)]],
                      uint2 g [[thread_position_in_grid]]) {
        if (g.x >= j.w || g.y >= j.h) { return; }
        float m = metres.read(g).r, d = bilinear(net, (float2(g) + 0.5f) / float2(j.w, j.h)).r;
        bool ok = isfinite(m) && m > 0.0f && isfinite(d);
        out.write(ok ? float4(1.0f / m - (j.s * d + j.t), 1.0f, 0.0f, 0.0f) : float4(0.0f), g);
    }

    // DETAIL: a box blur of the residual and its weight, along x (pass 0) or y (pass 1)
    kernel void blur(texture2d<float, access::read> in [[texture(0)]],
                     texture2d<float, access::write> out [[texture(1)]],
                     constant Fit &j [[buffer(0)]],
                     constant uint &pass [[buffer(1)]],
                     uint2 g [[thread_position_in_grid]]) {
        if (g.x >= j.w || g.y >= j.h) { return; }
        int2 step = pass ? int2(0, 1) : int2(1, 0), size = int2(j.w, j.h);
        float2 sum = float2(0.0f);
        for (int k = -int(j.r); k <= int(j.r); k++) { sum += in.read(uint2(clamp(int2(g) + step * k, int2(0), size - 1))).rg; }
        out.write(float4(sum, 0.0f, 0.0f), g);
    }

    // DETAIL, on the network's grid: its line plus the sensor's smoothed residual there, so the shape at large is the sensor's and
    // the edges and folds below the blur are the network's; metres out, none where nothing was measured near
    kernel void fuse(texture2d<float, access::read> net [[texture(0)]],
                     texture2d<float, access::read> lp [[texture(1)]],
                     texture2d<float, access::write> metres [[texture(2)]],
                     constant Fit &j [[buffer(0)]],
                     uint2 g [[thread_position_in_grid]]) {
        if (g.x >= j.w || g.y >= j.h) { return; }
        float4 a = bilinear(lp, (float2(g) + 0.5f) / float2(j.w, j.h));
        float z = j.s * net.read(g).r + j.t + (a.g > 0.0f ? a.r / a.g : 0.0f);
        metres.write(float4(a.g >= 0.5f && isfinite(z) && z > 0.0f ? 1.0f / z : 0.0f), g);
    }

    // a pixel of DEPTH at the picture's size, where something was measured: inside a surface the grid's own between its pixels (the
    // sensor's, or the network's folds), so the picture's patterns never become relief; at an edge (the measured ones around it more
    // than 6% apart, Frames.Clean's) the one
    // of them nearest the guided filter's line (its coefficients times the picture's Y, Cb, Cr), so nothing hangs between a face and
    // the wall and the edge sits on the picture's
    kernel void deep(texture2d<float, access::sample> luma [[texture(0)]],
                     texture2d<float, access::sample> chroma [[texture(1)]],
                     texture2d<float, access::read> coef [[texture(2)]],
                     texture2d<float, access::read> inv [[texture(3)]],
                     texture2d<float, access::sample> has [[texture(4)]],
                     device ushort *out [[buffer(0)]],
                     constant Deep &j [[buffer(1)]],
                     constant float *q [[buffer(2)]],
                     uint2 g [[thread_position_in_grid]]) {
        if (g.x >= j.w || g.y >= j.h) { return; }
        constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
        float2 p = stored(float2(g.x + 0.5f, g.y + 0.5f), j.w, j.h, j.turns, j.mirror);
        float z = 0.0f;
        if (has.sample(s, p).r >= 0.5f) {
            float4 k = bilinear(coef, p);
            float line = dot(k.rgb, float3(luma.sample(s, p).r, chroma.sample(s, p).rg)) + k.a;
            int2 size = int2(inv.get_width(), inv.get_height()), c = int2(floor(p * float2(size) - 0.5f));
            float2 f = fract(p * float2(size) - 0.5f);
            float lo = 1e9f, hi = 0.0f, sum = 0.0f, ws = 0.0f, v[4];
            for (int n = 0; n < 4; n++) {
                v[n] = inv.read(uint2(clamp(c + int2(n & 1, n >> 1), int2(0), size - 1))).r;
                if (v[n] > 0.0f) {
                    float w = ((n & 1) ? f.x : 1.0f - f.x) * ((n >> 1) ? f.y : 1.0f - f.y);
                    lo = min(lo, v[n]); hi = max(hi, v[n]); sum += w * v[n]; ws += w;
                }
            }
            z = ws > 0.0f ? sum / ws : 0.0f;
            if (!isfinite(z) || z <= 0.0f || hi - lo > 0.06f * hi) {
                float to = isfinite(line) && line > 0.0f ? line : z, best = 0.0f;
                for (int n = 0; n < 4; n++) { if (v[n] > 0.0f && (best == 0.0f || abs(v[n] - to) < abs(best - to))) { best = v[n]; } }
                z = best;
            }
        }
        out[g.y * j.w + g.x] = deepCode(z, j, q);
    }
    """
    private enum Kind { case uyvy, uyva, p216 }

    private final class Source {
        let kind: String
        var send: OpaquePointer?                            // NDI's sender (NDIlib_send_instance_t: an opaque struct's pointer)
        var asked = "", full = ""                           // the name it was made with; the one NDI shows (MACHINE (NAME KIND))
        var ring: [MTLBuffer] = [], next = 0, busy = false   // NDI reads a frame until the next one is sent: three, taken in turn
        var metas: [UnsafeMutablePointer<CChar>?] = [nil, nil, nil]   // each frame's metadata, alive as long as its frame
        var w = 0, h = 0, frames = 0, count = 0, fps = 0, countAt = 0.0, last = 0.0, thumbAt = 0.0
        var watchers = 0, tally = 0                         // receivers; tally: 1 preview, 2 program, 3 both
        var range: (near: Float, far: Float)?, rangeAt = 0.0   // DEPTH's AUTO, eased; nil: not yet
        var aim: (near: Float, far: Float)?                 // the range AUTO eases to
        var eq: [Float]?                                    // EQ's 33 distances, eased
        var card: [UInt16] = []                             // DEPTH's codes at the camera's size: the card's picture, and what goes out enlarged
        let line: DispatchQueue                             // its sends (out)
        init(_ kind: String) { self.kind = kind; line = DispatchQueue(label: "ndi." + kind.lowercased(), qos: .userInitiated) }
    }

    /// DEPTH's textures on a grid (sharpen), the depth camera's or DETAIL's network's: metres (the CPU's cleaned ones, or DETAIL's
    /// fused), 1/distance, the guided filter's weights, measured or not, the picture averaged to it, the filter's coefficients; on
    /// the camera's, DETAIL's residual and its blur
    private final class Low {
        let w: Int, h: Int, m: MTLTexture, inv: MTLTexture, weight: MTLTexture, has: MTLTexture, guide: MTLTexture, coef: MTLTexture, rg: MTLTexture, lp: MTLTexture
        init?(_ gpu: MTLDevice, _ w: Int, _ h: Int) {
            func make(_ f: MTLPixelFormat, shared: Bool = false) -> MTLTexture? {
                let t = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: w, height: h, mipmapped: false)
                t.usage = [.shaderRead, .shaderWrite]; t.storageMode = shared ? .shared : .private
                return gpu.makeTexture(descriptor: t)
            }
            guard let m = make(.r32Float, shared: true), let inv = make(.r32Float), let weight = make(.r32Float), let has = make(.r8Unorm),
                  let guide = make(.rgba32Float), let coef = make(.rgba32Float), let rg = make(.rg32Float), let lp = make(.rg32Float) else { return nil }
            self.w = w; self.h = h; self.m = m; self.inv = inv; self.weight = weight; self.has = has; self.guide = guide; self.coef = coef; self.rg = rg; self.lp = lp
        }
    }

    private let queue = DispatchQueue(label: "ndi", qos: .userInitiated)
    private var set = Settings(), away = false, heat = ProcessInfo.processInfo.thermalState
    private let vid = Source("VIDEO"), dep = Source("DEPTH")
    private var timer: DispatchSourceTimer?, ready = false, broken = false, shown: NSDictionary?, saidOnce: Set<String> = []
    private let gpu = MTLCreateSystemDefaultDevice()
    private var commands: MTLCommandQueue?, kernel: MTLComputePipelineState?, cache: CVMetalTextureCache?, none: MTLTexture?, matter: ARMatteGenerator?
    private var lowKernel: MTLComputePipelineState?, deepKernel: MTLComputePipelineState?, guided: MPSImageGuidedFilter?, low: Low?   // DEPTH's GPU way (sharpen)
    private var residKernel: MTLComputePipelineState?, blurKernel: MTLComputePipelineState?, fuseKernel: MTLComputePipelineState?, lowNet: Low?, net: MTLTexture?   // DETAIL's (the network's grid)
    private let ml = Detail(), mlQueue = DispatchQueue(label: "ndi.detail", qos: .userInitiated)   // DETAIL's network, on its own queue
    private var mlBusy = false, waiting: Depth?   // it is running; the newest frame waiting for it
    private let ci = CIContext(), hist = UnsafeMutablePointer<UInt32>.allocate(capacity: 10000)   // the cards' JPEGs; AUTO's depths, a bin a millimetre to 10 m (EQ wants a face's millimetres)
    private let clean = Frames.Clean(), deep = DispatchSemaphore(value: 1)   // DEPTH's clean-up and its memory of the last frame; a depth frame at a time
    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private static let sureAll: UnsafeMutablePointer<UInt8> = { let p = UnsafeMutablePointer<UInt8>.allocate(capacity: 1); p.pointee = 2; return p }()   // no confidence map: every pixel sure

    init() {
        if let gpu {
            commands = gpu.makeCommandQueue()
            CVMetalTextureCacheCreate(nil, nil, gpu, nil, &cache)
            none = gpu.makeTexture(descriptor: MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 1, height: 1, mipmapped: false))   // MATTE off: an alpha nobody reads
            queue.async { [weak self] in
                do { self?.kernel = try gpu.makeLibrary(source: NDI.shader, options: nil).makeFunction(name: "video").map { try gpu.makeComputePipelineState(function: $0) } }
                catch { self?.said("NDI · VIDEO CAN'T START ITS SHADER: " + error.localizedDescription.uppercased()) }
                do {   // exact maths: none (NaN, 0) must stay none
                    let o = MTLCompileOptions(); o.mathMode = .safe
                    let lib = try gpu.makeLibrary(source: NDI.shader + NDI.deepShader, options: o)
                    func make(_ n: String) throws -> MTLComputePipelineState? { try lib.makeFunction(name: n).map { try gpu.makeComputePipelineState(function: $0) } }
                    self?.lowKernel = try make("low"); self?.deepKernel = try make("deep")
                    self?.residKernel = try make("resid"); self?.blurKernel = try make("blur"); self?.fuseKernel = try make("fuse")
                } catch {
                    self?.said("NDI · DEPTH CAN'T START ITS SHADER (IT GOES THE SLOW WAY): " + error.localizedDescription.uppercased())
                }
            }
            guided = MPSImageGuidedFilter(device: gpu, kernelDiameter: 5); guided?.epsilon = 0.004   // Apple's point-cloud sample's
        }
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            let h = ProcessInfo.processInfo.thermalState
            self?.queue.async { self?.cool(h) }
        }
    }

    /// What the page wants now (any thread)
    func configure(_ s: Settings) { queue.async { self.set = s; self.refresh() } }

    /// SensorLove off the screen, or back: the senders go and come again (iOS takes the camera; a sender kept over it is not found again)
    func leave(_ gone: Bool) { queue.async { self.away = gone; self.refresh() } }

    func picture(_ p: Picture) { queue.async { self.take(p) } }   // from a camera's queue
    func depth(_ d: Depth) { queue.async { self.arrive(d) } }   // from a camera's queue

    /// A depth frame comes. With DETAIL AI the network runs on this frame's own picture first and the rest follows when it is done,
    /// so its shape never trails the sensor's. The network takes one frame at a time; the newest waits for it, an older one waiting
    /// is dropped. Then (and without
    /// AI at once) one frame at a time until NDI has it: a frame that comes meanwhile is dropped, so no lag piles up
    private func arrive(_ d: Depth) {
        if set.detail, Detail.built, d.guide != nil, dep.send != nil, dep.watchers > 0, rate > 0 {
            if mlBusy { waiting = d } else { think(d) }
            return
        }
        waiting = nil
        guard deep.wait(timeout: .now()) == .success else { return }
        take(d, nil) { self.deep.signal() }
    }

    private func think(_ d: Depth) {   // the network on d's picture (its queue), then d on NDI's
        guard let g = d.guide else { return }
        mlBusy = true
        mlQueue.async { [weak self] in
            guard let self else { return }
            let n = self.ml.run(g), ms = self.ml.ms
            self.queue.async {
                if let w = self.waiting { self.waiting = nil; self.think(w) } else { self.mlBusy = false }
                guard self.deep.wait(timeout: .now()) == .success else { return }
                self.take(d, n.map { (map: $0, ms: ms) }) { self.deep.signal() }
            }
        }
    }

    /// The mic (Phone's tap), for VIDEO with AUDIO on: its channels one after the other (NDI's FLTP)
    func audio(_ b: AVAudioPCMBuffer) {
        guard let ch = b.floatChannelData, !b.format.isInterleaved, b.frameLength > 0 else { return }
        let n = Int(b.frameLength), c = Int(b.format.channelCount), rate = Int(b.format.sampleRate)
        var d = Data(count: n * c * 4)
        d.withUnsafeMutableBytes { o in for i in 0..<c { memcpy(o.baseAddress! + i * n * 4, ch[i], n * 4) } }
        queue.async { self.sound(d, rate: rate, channels: c, samples: n) }
    }

    // MARK: the senders

    private func refresh() {
        for (src, want) in [(vid, set.video), (dep, set.depth)] {
            let on = want && !away && NDI.built && !broken, name = set.name + " " + src.kind
            if src.send != nil, !on || src.asked != name { drop(src) }   // off, or renamed: a new one
            if on, src.send == nil { start(src, name) }
        }
        let live = vid.send != nil || dep.send != nil
        if live, timer == nil {
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: 0.5)
            t.setEventHandler { [weak self] in self?.poll() }
            t.resume(); timer = t
        } else if !live, let t = timer { t.cancel(); timer = nil }
        poll()
    }

    private func start(_ src: Source, _ name: String) {
        #if NDI
        if !ready {
            // NDI puts the machine's name before a source's; on iOS that is "LOCALHOST". Its config file names it (machinename; the
            // folder in NDI_CONFIG_DIR, both in libndi_ios.a's strings), read as it starts
            if let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("NDI") {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? Data("{\"ndi\":{\"machinename\":\"IPHONE\"}}".utf8).write(to: dir.appendingPathComponent("ndi-config.v1.json"))
                setenv("NDI_CONFIG_DIR", dir.path, 1)
            }
            ready = NDIlib_initialize(); if !ready { broken = true; return say("NDI · THIS PHONE CAN'T RUN IT") }
        }
        var c = NDIlib_send_create_t()
        c.clock_video = false; c.clock_audio = false   // the camera keeps the time: a clocked send would wait for its slot
        src.send = name.withCString { n in c.p_ndi_name = n; return NDIlib_send_create(&c) }
        guard let s = src.send else { return say("NDI · " + src.kind + " DIDN'T START") }
        src.asked = name
        let who = "<ndi_product long_name=\"SensorLove\" short_name=\"SensorLove\" manufacturer=\"sensor.love\" version=\"\(NDI.version)\" model_name=\"iPhone\" session=\"default\"/>"
        who.withCString { p in   // NDI's own element: who sends it, to every receiver once
            var m = NDIlib_metadata_frame_t()
            m.timecode = Int64.max; m.p_data = UnsafeMutablePointer(mutating: p)
            NDIlib_send_add_connection_metadata(s, &m)
        }
        src.full = NDIlib_send_get_source_name(s).flatMap { $0.pointee.p_ndi_name.map { String(cString: $0) } } ?? name
        #endif
    }

    private func drop(_ src: Source) {
        #if NDI
        if let s = src.send { src.line.sync { NDIlib_send_send_video_async_v2(s, nil); NDIlib_send_destroy(s) } }   // after its queued frame; the frame NDI holds let go first
        #endif
        src.send = nil; src.asked = ""; src.full = ""; src.busy = false; src.watchers = 0; src.tally = 0; src.fps = 0; src.range = nil; src.aim = nil; src.eq = nil
        src.ring = []; src.metas.forEach { free($0) }; src.metas = [nil, nil, nil]
    }

    private func poll() {   // the receivers and the tally from NDI, the rate from what went out; the page hears what changed
        let now = CACurrentMediaTime()
        for src in [vid, dep] {
            #if NDI
            if let s = src.send {
                src.watchers = Int(NDIlib_send_get_no_connections(s, 0))
                var t = NDIlib_tally_t()
                if NDIlib_send_get_tally(s, &t, 0) { src.tally = (t.on_program ? 2 : 0) + (t.on_preview ? 1 : 0) }
            }
            #endif
            if now - src.countAt >= 1 { src.fps = src.countAt > 0 ? Int((Double(src.count) / (now - src.countAt)).rounded()) : 0; src.count = 0; src.countAt = now }
        }
        func one(_ s: Source) -> [Any] { [s.send != nil ? 1 : 0, s.watchers, s.tally, s.w, s.h, s.fps, s.full] }
        let st: NSDictionary = ["built": NDI.built, "video": one(vid), "depth": one(dep), "hot": heat == .critical ? 2 : heat == .serious ? 1 : 0]
        if st != shown { shown = st; told(st as? [String: Any] ?? [:]) }
    }

    private func cool(_ h: ProcessInfo.ThermalState) {
        let was = heat
        heat = h
        if h == .critical, was != .critical { said("NDI · TOO HOT: PAUSED UNTIL IT COOLS DOWN") }
        else if h == .serious, was != .serious { said("NDI · HOT: FULL QUALITY KEPT, IT PAUSES IF IT GETS TOO HOT") }
        poll()
    }

    private var rate: Double { heat == .critical ? 0 : Double(set.hz) }   // quality first: warm keeps it all, critical pauses until it cools

    // MARK: frames

    private func take(_ p: Picture) {
        let src = vid
        preview(p, src)
        guard let s = src.send, src.watchers > 0, !src.busy, rate > 0, p.t - src.last >= 1 / rate - 0.004,
              let q = commands, let kernel, let cache, let none else { return }
        let pw = CVPixelBufferGetWidth(p.px), ph = CVPixelBufferGetHeight(p.px), up = Frames.size(pw, ph, p.look)
        let lines = !set.hd ? 720 : set.max ? Int.max : 1080, k = min(1, Double(lines) / Double(min(up.w, up.h)))
        let w = Int((Double(up.w) * k / 2).rounded()) * 2, h = Int((Double(up.h) * k / 2).rounded()) * 2   // even: UYVY's pairs
        let alpha = set.matte && p.ar != nil
        guard case let (i, buf)? = slot(src, w * h * (alpha ? 3 : 2)), let luma = texture(p.px, 0, .r8Unorm, cache), let chroma = texture(p.px, 1, .rg8Unorm, cache),
              let cb = q.makeCommandBuffer() else { return }
        var people = none
        if alpha, let f = p.ar, let gpu {   // ARKit's matte, refined on the GPU, written in this same command buffer before the conversion reads it
            if matter == nil { matter = ARMatteGenerator(device: gpu, matteResolution: .half) }
            if let m = matter?.generateMatte(from: f, commandBuffer: cb) { people = m }
        }
        guard let enc = cb.makeComputeCommandEncoder() else { return }
        let full = CVPixelBufferGetPixelFormatType(p.px) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let rows = Frames.convert(from: Frames.standard(of: p.px, full ? .bt601 : .bt709), full: full, to: Frames.standard(w: w, h: h))
        var job = Job(w: UInt32(w), h: UInt32(h), turns: UInt32(p.look.turns), mirror: p.look.mirror ? 1 : 0, y: rows[0], cb: rows[1], cr: rows[2], alpha: alpha ? 1 : 0)
        enc.setComputePipelineState(kernel)
        enc.setTexture(CVMetalTextureGetTexture(luma), index: 0)
        enc.setTexture(CVMetalTextureGetTexture(chroma), index: 1)
        enc.setTexture(people, index: 2)
        enc.setBuffer(buf, offset: 0, index: 0)
        enc.setBytes(&job, length: MemoryLayout<Job>.stride, index: 1)
        enc.dispatchThreads(MTLSize(width: w / 2, height: h, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1))
        enc.endEncoding()
        src.busy = true; src.last = p.t
        let lens = p.k.map { Frames.scaled(Frames.lens($0, w: Float(pw), h: Float(ph), p.look), Float(w) / Float(up.w)) }
        let meta = Frames.meta("VIDEO", frame: src.frames, t: p.t, w: w, h: h, k: lens, pose: p.pose.flatMap { Frames.pose($0, p.look) }, range: nil)
        cb.addCompletedHandler { [weak self] _ in
            _ = (luma, chroma)   // the frame's textures (and the frame) held until the GPU is done with them
            self?.queue.async { self?.out(src, s, i, buf, alpha ? .uyva : .uyvy, w: w, h: h, meta: meta, at: p.t) }
        }
        cb.commit()
    }

    /// A depth frame: cleaned and ranged on the CPU at the depth camera's size, then to NDI the GPU's way (sharpen; with DETAIL AI
    /// net, the network's map of this frame, tied to it first) or, without its picture or the GPU's shaders, made bigger here
    /// (Frames.enlarge). done: when NDI has it, or nothing goes
    private func take(_ d: Depth, _ net: (map: [Float], ms: Double)?, _ done: @escaping () -> Void) {
        let src = dep
        let sending = src.send != nil && src.watchers > 0 && rate > 0 && d.t - src.last >= 1 / rate - 0.004, card = d.t - src.thumbAt >= 1 / NDI.cardHz
        guard sending || card, CVPixelBufferGetPixelFormatType(d.px) == kCVPixelFormatType_DepthFloat32 else { return done() }
        if card { src.thumbAt = d.t }
        CVPixelBufferLockBaseAddress(d.px, .readOnly); defer { CVPixelBufferUnlockBaseAddress(d.px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(d.px) else { return done() }
        let dw = CVPixelBufferGetWidth(d.px), dh = CVPixelBufferGetHeight(d.px), up = Frames.size(dw, dh, d.look), all = (UnsafeRawPointer(NDI.sureAll), 0, 0)
        // edges snapped, holes filled, steadied. ARKit's confidence weighs in the guided filter instead (sharpen): cut here, it would
        // leave ragged holes at every edge
        let m = clean.run(base, row: CVPixelBufferGetBytesPerRow(d.px), sure: all, w: dw, h: dh, steady: d.steady)
        let r = range(src, d.t, UnsafeMutableRawPointer(m), dw * 4, all, w: dw, h: dh)
        func codes() {   // the codes at the depth camera's size, stood up a row at a time (Frames.walk): the card's picture, DEPTH the CPU's way
            let lut = r.eq.map { Frames.eqCodes($0, steps: 4096) }, scale = 4095 / max(r.far - r.near, 0.001)
            func code(_ v: Float) -> UInt16 {   // EQ by its table, else by 1/distance
                guard let lut else { return Frames.depthCode(v, near: r.near, far: r.far) }
                guard v.isFinite, v > 0, v <= r.far else { return 4096 }
                return v <= r.near ? 60160 : lut[min(Int((v - r.near) * scale + 0.5), 4095)]
            }
            if src.card.count != up.w * up.h { src.card = Array(repeating: 4096, count: up.w * up.h) }
            src.card.withUnsafeMutableBufferPointer { o in
                for y in 0..<up.h {
                    let k = Frames.walk(y, w: dw, h: dh, d.look), step = k.dy * dw + k.dx, line = o.baseAddress! + y * up.w
                    var i = k.y * dw + k.x
                    for x in 0..<up.w { line[x] = code(m[i]); i += step }
                }
            }
        }
        let fx = d.k.map { Frames.lens($0, w: Float(dw), h: Float(dh), d.look)[0][0] } ?? Float(up.w)   // the card's light reads true slopes with it
        guard sending, let s = src.send else {   // no one watching: the card from the sensor's own codes
            if card { codes(); src.card.withUnsafeBufferPointer { preview(depth: $0.baseAddress!, w: up.w, h: up.h, r, fx: fx) } }
            return done()
        }
        func slow() {   // without the picture or the GPU's shaders: the codes made bigger, long side 1920
            codes()
            if card { src.card.withUnsafeBufferPointer { preview(depth: $0.baseAddress!, w: up.w, h: up.h, r, fx: fx) } }
            let n = max(1, NDI.deepLong / max(up.w, up.h))
            guard case let (i, buf)? = slot(src, up.w * up.h * n * n * 4, grey: true) else { return done() }   // P216's 4 bytes a pixel
            src.card.withUnsafeBufferPointer { Frames.enlarge($0.baseAddress!, w: up.w, h: up.h, by: n, into: buf.contents().assumingMemoryBound(to: UInt16.self)) }
            src.last = d.t
            let meta = Frames.meta("DEPTH", frame: src.frames, t: d.t, w: up.w * n, h: up.h * n, k: d.k.map { Frames.scaled(Frames.lens($0, w: Float(dw), h: Float(dh), d.look), Float(n)) }, pose: d.pose.flatMap { Frames.pose($0, d.look) }, range: (r.near, r.far), eq: r.eq)
            out(src, s, i, buf, .p216, w: up.w * n, h: up.h * n, meta: meta, at: d.t, then: done)
        }
        guard let g = d.guide else { return slow() }
        // DETAIL: this frame's own network map, tied to this frame's sensor
        let fit = net.flatMap { Frames.fit(m, w: dw, h: dh, net: $0.map, nw: Detail.w, nh: Detail.h) }
        var tie: (net: [Float], s: Float, t: Float, err: Float, ms: Double)? = nil
        if let n = net, let f = fit, f.s > 0, f.err < 0.6 { tie = (n.map, f.s, f.t, f.err, n.ms) }   // a loose gate, so frames do not flick between AI and SENSOR: the sensor's own shape is added anyway
        if !sharpen(src, s, d, g, m, dw, dh, r, tie, card, done) { slow() }
    }

    /// DEPTH at its picture's size (VIDEO's, pixel for pixel, as SIZE says) on the GPU, the guided filter's way (He's; Apple's for
    /// LiDAR in its point-cloud sample, and its engineers' advice: "use a guided filter to upsample the depth map based on the rgb
    /// data"). On the depth camera's grid, in each 5 x 5, 1/distance is fitted as a line of the picture's Y, Cb, Cr (MPS; ARKit's
    /// confidence its weights: an unsure pixel pulls less and leaves no hole); at each pixel of the picture that line places the
    /// edges, so DEPTH's edges are the picture's, and inside a surface the grid's own is kept (deep). With DETAIL AI (ai: the
    /// network's map and its tie, Frames.fit) the grid is the network's: its line plus the sensor's residual smoothed over about a
    /// 64th of the frame (resid, blur, fuse; the sensor's shape at large, the network's edges and folds below that). False when it
    /// cannot: nothing sent, done not called
    private func sharpen(_ src: Source, _ s: OpaquePointer, _ d: Depth, _ g: CVPixelBuffer, _ m: UnsafeMutablePointer<Float>, _ dw: Int, _ dh: Int,
                         _ r: (near: Float, far: Float, eq: [Float]?), _ ai: (net: [Float], s: Float, t: Float, err: Float, ms: Double)?, _ card: Bool, _ done: @escaping () -> Void) -> Bool {
        guard let gpu, let q = commands, let cache, let none, let lowK = lowKernel, let deepK = deepKernel, let filter = guided,
              CVPixelBufferGetPlaneCount(g) == 2, let gl = texture(g, 0, .r8Unorm, cache), let gc = texture(g, 1, .rg8Unorm, cache) else { return false }
        if low?.w != dw || low?.h != dh { low = Low(gpu, dw, dh) }
        if ai != nil, lowNet == nil { lowNet = Low(gpu, Detail.w, Detail.h) }
        if ai != nil, net == nil {
            let t = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: Detail.w, height: Detail.h, mipmapped: false)
            t.usage = .shaderRead; t.storageMode = .shared
            net = gpu.makeTexture(descriptor: t)
        }
        guard let low else { return false }
        let gw = CVPixelBufferGetWidth(g), gh = CVPixelBufferGetHeight(g), big = Frames.size(gw, gh, d.look)
        let lines = !set.hd ? 720 : set.max ? Int.max : 1080, k = min(1, Double(lines) / Double(min(big.w, big.h)))
        let w = Int((Double(big.w) * k / 2).rounded()) * 2, h = Int((Double(big.h) * k / 2).rounded()) * 2   // even: P216's pairs
        guard case let (i, buf)? = slot(src, w * h * 4, grey: true), let cb = q.makeCommandBuffer(), let e1 = cb.makeComputeCommandEncoder() else { return false }
        low.m.replace(region: MTLRegionMake2D(0, 0, dw, dh), mipmapLevel: 0, withBytes: m, bytesPerRow: dw * 4)
        var grid = low
        if let ai, let ln = lowNet, let nt = net, let rk = residKernel, let bk = blurKernel, let fk = fuseKernel {
            nt.replace(region: MTLRegionMake2D(0, 0, Detail.w, Detail.h), mipmapLevel: 0, withBytes: ai.net, bytesPerRow: Detail.w * 4)
            // the sensor's shape over 21 of its pixels: TrueDepth's a 30th of the frame, the LiDAR's a 15th (its finer shape is the camera's own guess)
            var onSensor = FitJob(w: UInt32(dw), h: UInt32(dh), s: ai.s, t: ai.t, r: 10), onNet = FitJob(w: UInt32(Detail.w), h: UInt32(Detail.h), s: ai.s, t: ai.t, r: 0)
            func run(_ kernel: MTLComputePipelineState, _ ts: [MTLTexture], _ j: inout FitJob, pass: UInt32? = nil) {
                e1.setComputePipelineState(kernel)
                for (n, t) in ts.enumerated() { e1.setTexture(t, index: n) }
                e1.setBytes(&j, length: MemoryLayout<FitJob>.stride, index: 0)
                if var p = pass { e1.setBytes(&p, length: MemoryLayout<UInt32>.stride, index: 1) }
                e1.dispatchThreads(MTLSize(width: Int(j.w), height: Int(j.h), depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1))
            }
            run(rk, [low.m, nt, low.rg], &onSensor)                                                   // the sensor against the network's line
            run(bk, [low.rg, low.lp], &onSensor, pass: 0); run(bk, [low.lp, low.rg], &onSensor, pass: 1)   // smoothed both ways, back in rg
            run(fk, [nt, low.rg, ln.m], &onNet)                                                       // the two together, on the network's grid
            grid = ln
        }
        let sure = grid === low ? d.sure.flatMap { CVPixelBufferGetWidth($0) == dw && CVPixelBufferGetHeight($0) == dh ? texture($0, 0, .r8Unorm, cache) : nil } : nil
        var lj = LowJob(w: UInt32(grid.w), h: UInt32(grid.h), sx: Float(gw) / Float(grid.w), sy: Float(gh) / Float(grid.h), conf: sure != nil ? 1 : 0)
        let ins: [MTLTexture?] = [grid.m, CVMetalTextureGetTexture(gl), CVMetalTextureGetTexture(gc), sure.flatMap(CVMetalTextureGetTexture) ?? none, grid.inv, grid.weight, grid.has, grid.guide]
        e1.setComputePipelineState(lowK)
        for (n, t) in ins.enumerated() { e1.setTexture(t, index: n) }
        e1.setBytes(&lj, length: MemoryLayout<LowJob>.stride, index: 0)
        e1.dispatchThreads(MTLSize(width: grid.w, height: grid.h, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1))
        e1.endEncoding()
        filter.encodeRegression(to: cb, sourceTexture: grid.inv, guidanceTexture: grid.guide, weightsTexture: grid.weight, destinationCoefficientsTexture: grid.coef)
        guard let e2 = cb.makeComputeCommandEncoder() else { return false }
        var dj = DeepJob(w: UInt32(w), h: UInt32(h), turns: UInt32(d.look.turns), mirror: d.look.mirror ? 1 : 0, eq: r.eq != nil ? 1 : 0, near: r.near, far: r.far)
        let eq = r.eq ?? [Float](repeating: 0, count: 33), outs: [MTLTexture?] = [CVMetalTextureGetTexture(gl), CVMetalTextureGetTexture(gc), grid.coef, grid.inv, grid.has]
        e2.setComputePipelineState(deepK)
        for (n, t) in outs.enumerated() { e2.setTexture(t, index: n) }
        e2.setBuffer(buf, offset: 0, index: 0)
        e2.setBytes(&dj, length: MemoryLayout<DeepJob>.stride, index: 1)
        e2.setBytes(eq, length: eq.count * MemoryLayout<Float>.stride, index: 2)
        e2.dispatchThreads(MTLSize(width: w, height: h, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1))
        e2.endEncoding()
        src.last = d.t
        let up = Frames.size(dw, dh, d.look), lens = d.k.map { Frames.scaled(Frames.lens($0, w: Float(dw), h: Float(dh), d.look), Float(w) / Float(up.w)) }
        let plain = Frames.meta("DEPTH", frame: src.frames, t: d.t, w: w, h: h, k: lens, pose: d.pose.flatMap { Frames.pose($0, d.look) }, range: (r.near, r.far), eq: r.eq)
        let meta = ai.map { grid !== low ? String(plain.dropLast(2)) + String(format: " detail=\"ai\" ai=\"%.1f\" fit=\"%.4f\"/>", $0.ms, $0.err) : plain } ?? plain   // the network's milliseconds; half the pixels within this of its line
        let fx = lens?[0][0] ?? Float(w)
        cb.addCompletedHandler { [weak self] _ in
            _ = (gl, gc, sure)   // the picture's and the confidence's textures (and their buffers) held until the GPU is done
            self?.queue.async {
                if card { self?.preview(depth: buf.contents().assumingMemoryBound(to: UInt16.self), w: w, h: h, r, fx: fx) }   // the card: what goes out
                self?.out(src, s, i, buf, .p216, w: w, h: h, meta: meta, at: d.t, then: done)
            }
        }
        cb.commit()
        return true
    }

    /// DEPTH's range. FAR's metres: from 20 cm, as near as the depth cameras see. AUTO: the scene's, from a histogram of every 4th
    /// pixel each way: from 3% in front of its nearest 0.2% (the tip of a nose stays a grey, not clipped white) to its 98th
    /// percentile, 5% more at the far end, 30 cm at least. FACE: 40 cm from there: a face held up to the camera gets the greys, the
    /// room behind goes black. Steady: a new aim only when the scene moved more than 4% (breathing and the sensor's noise do not pump
    /// the picture), eased to: out in 0.15 s, in over 1.5 s (auto exposure's way: faster out than in). EQ: the distances at 33 even
    /// shares of the picture, from its nearest 0.5% to its farthest 0.5%, each eased over 0.4 s, so it does not flicker
    private func range(_ src: Source, _ t: Double, _ base: UnsafeMutableRawPointer, _ row: Int, _ sure: (UnsafeRawPointer, Int, Int), w: Int, h: Int) -> (near: Float, far: Float, eq: [Float]?) {
        guard set.auto else { src.eq = nil; return (NDI.closest, set.far, nil) }
        hist.update(repeating: 0, count: 10000)
        var n = 0
        for y in stride(from: 0, to: h, by: 4) {
            for x in stride(from: 0, to: w, by: 4) where sure.0.load(fromByteOffset: y * sure.1 + x * sure.2, as: UInt8.self) >= 1 {
                let m = base.load(fromByteOffset: y * row + x * 4, as: Float32.self)
                if m > 0, m < 10 { hist[Int(m * 1000)] += 1; n += 1 }
            }
        }
        guard n > 50 else { return src.range.map { ($0.near, $0.far, src.eq) } ?? (NDI.closest, set.far, nil) }   // nothing to go by: as it was
        func at(_ qs: [Double]) -> [Float] {   // the distances under which those shares of the pixels are (rising), in one walk
            var out: [Float] = [], k = 0, sum = 0
            for q in qs {
                let want = Int(Double(n) * q)
                while k < 9999, sum + Int(hist[k]) <= want { sum += Int(hist[k]); k += 1 }
                out.append(Float(k) / 1000)
            }
            return out
        }
        if set.eq {
            var want = at((0...32).map { 0.005 + 0.99 * Double($0) / 32 })
            want[32] = max(want[32], want[0] + 0.05)   // a flat wall: 5 cm at least
            let a = src.eq == nil ? 1 : 1 - exp(-Float(min(max(t - src.rangeAt, 0), 1)) / 0.4)
            let q = src.eq.map { was in zip(was, want).map { $0 + ($1 - $0) * a } } ?? want
            src.eq = q; src.range = (q[0], q[32]); src.rangeAt = t
            return (q[0], q[32], q)
        }
        src.eq = nil
        let p = at([0.002, 0.98]), lo = max(p[0] * 0.97, NDI.closest), want = (near: lo, far: set.face ? lo + 0.4 : max((p[1] + 0.01) * 1.05, lo + 0.3))
        if let a = src.aim, abs(want.near - a.near) <= 0.04 * a.near, abs(want.far - a.far) <= 0.04 * a.far {} else { src.aim = want }
        let aim = src.aim ?? want
        guard let was = src.range else { src.range = aim; src.rangeAt = t; return (aim.near, aim.far, nil) }
        let dt = Float(min(max(t - src.rangeAt, 0), 1))
        func ease(_ v: Float, _ to: Float, opens: Bool) -> Float { v + (to - v) * (1 - exp(-dt / (opens ? 0.15 : 1.5))) }
        let now = (near: ease(was.near, aim.near, opens: aim.near < was.near), far: ease(was.far, aim.far, opens: aim.far > was.far))
        src.range = now; src.rangeAt = t
        return (now.near, now.far, nil)
    }

    /// A frame ready in slot i: to NDI on the source's own queue (NDI reads it until the next one; its send waits while the last is
    /// still being encoded, so VIDEO and DEPTH each wait only for their own). Its metadata gets age: milliseconds from the capture
    /// (at, the camera's clock) to here. then: on the NDI queue once NDI has it (the next frame may start). The sender may have gone
    private func out(_ src: Source, _ s: OpaquePointer, _ i: Int, _ buf: MTLBuffer, _ kind: Kind, w: Int, h: Int, meta: String, at: Double, then: @escaping () -> Void = {}) {
        guard src.send == s else { src.busy = false; return then() }
        free(src.metas[i]); src.metas[i] = strdup(String(meta.dropLast(2)) + String(format: " age=\"%.1f\"/>", (CACurrentMediaTime() - at) * 1000))
        let m = src.metas[i], hz = set.hz
        src.line.async { [weak self] in
            #if NDI
            var f = NDIlib_video_frame_v2_t()
            f.xres = Int32(w); f.yres = Int32(h)
            switch kind {
            case .uyvy: f.FourCC = NDIlib_FourCC_video_type_UYVY
            case .uyva: f.FourCC = NDIlib_FourCC_video_type_UYVA
            case .p216: f.FourCC = NDIlib_FourCC_video_type_P216
            }
            f.frame_rate_N = Int32(hz); f.frame_rate_D = 1
            f.picture_aspect_ratio = 0                          // square pixels
            f.frame_format_type = NDIlib_frame_format_type_progressive
            f.timecode = Int64.max                              // NDI's: synthesized
            f.p_data = buf.contents().assumingMemoryBound(to: UInt8.self)
            f.line_stride_in_bytes = Int32(w * 2)               // UYVY two bytes a pixel; P216 two a sample; UYVA's alpha plane after, w a row
            f.p_metadata = UnsafePointer(m)
            NDIlib_send_send_video_async_v2(s, &f)
            #else
            _ = (s, buf, kind, m, hz)
            #endif
            self?.queue.async {
                src.busy = false
                if src.send == s { src.frames += 1; src.count += 1; src.w = w; src.h = h }
                then()
            }
        }
    }

    private func sound(_ d: Data, rate: Int, channels: Int, samples: Int) {
        guard set.audio, let s = vid.send, vid.watchers > 0, rate > 0 else { return }
        #if NDI
        d.withUnsafeBytes { p in
            var f = NDIlib_audio_frame_v3_t()
            f.sample_rate = Int32(rate); f.no_channels = Int32(channels); f.no_samples = Int32(samples)
            f.timecode = Int64.max
            f.FourCC = NDIlib_FourCC_audio_type_FLTP
            f.p_data = UnsafeMutablePointer(mutating: p.bindMemory(to: UInt8.self).baseAddress)
            f.channel_stride_in_bytes = Int32(samples * 4)
            NDIlib_send_send_audio_v3(s, &f)   // copied: done when it returns
        }
        #else
        _ = (d, s, channels, samples)
        #endif
    }

    /// The next of a source's three buffers (bytes long). A new size makes new ones, NDI made to let go of the old first
    private func slot(_ src: Source, _ bytes: Int, grey: Bool = false) -> (Int, MTLBuffer)? {
        if src.ring.first?.length != bytes {
            #if NDI
            if let s = src.send { src.line.sync { NDIlib_send_send_video_async_v2(s, nil) } }
            #endif
            guard let gpu else { return nil }
            src.ring = (0..<3).compactMap { _ in gpu.makeBuffer(length: bytes, options: .storageModeShared) }
            guard src.ring.count == 3 else { src.ring = []; return nil }
            if grey { for b in src.ring { let p = b.contents().assumingMemoryBound(to: UInt16.self); for j in bytes / 4 ..< bytes / 2 { p[j] = 32768 } } }   // P216's Cb and Cr: no colour, for good
        }
        let i = src.next
        src.next = (i + 1) % 3
        return (i, src.ring[i])
    }

    private func texture(_ px: CVPixelBuffer, _ plane: Int, _ f: MTLPixelFormat, _ cache: CVMetalTextureCache) -> CVMetalTexture? {   // a plane, or a one-plane buffer (plane 0)
        var t: CVMetalTexture?
        let planar = CVPixelBufferIsPlanar(px)
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, px, nil, f, planar ? CVPixelBufferGetWidthOfPlane(px, plane) : CVPixelBufferGetWidth(px),
                                                  planar ? CVPixelBufferGetHeightOfPlane(px, plane) : CVPixelBufferGetHeight(px), planar ? plane : 0, &t)
        return t
    }

    /// VIDEO's card: the picture as sent (stood up), small, in colour
    private func preview(_ p: Picture, _ src: Source) {
        guard p.t - src.thumbAt >= 1 / NDI.cardHz else { return }
        src.thumbAt = p.t
        let i = CIImage(cvPixelBuffer: p.px).oriented(Frames.orientation(p.look)), k = min(1, CGFloat(NDI.cardSide) / max(i.extent.width, i.extent.height))
        if let d = ci.jpegRepresentation(of: i.transformed(by: CGAffineTransform(scaleX: k, y: k)), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.7]) { thumb("video", d) }
    }

    /// DEPTH's card: its codes as sent (near white), small and grey (REAL draws it); and the same lit from the top left by its true
    /// slopes, depthshade (DITHER draws it: the shape, which the greys hide).
    /// fx: the lens in o's pixels
    private func preview(depth o: UnsafePointer<UInt16>, w: Int, h: Int, _ r: (near: Float, far: Float, eq: [Float]?), fx: Float) {
        let (tw, th) = NDI.small(w, h), f = fx * Float(tw) / Float(w)
        var g = [UInt8](repeating: 0, count: tw * th), u = [Float](repeating: 0, count: tw * th), lit = [UInt8](repeating: 0, count: tw * th)
        for y in 0..<th {
            let line = o + (y * h / th) * w
            for x in 0..<tw {
                let c = line[x * w / tw], i = y * tw + x
                g[i] = UInt8(max(0, Int(c) - 4096) * 255 / 56064)
                let m: Float? = r.eq != nil ? Frames.eqMetres(c, r.eq!) : Frames.metres(c, near: r.near, far: r.far)
                if let m, m > 0 { u[i] = 1 / m }   // 1/distance; 0 none
            }
        }
        for y in 1..<max(1, th - 1) {
            for x in 1..<max(1, tw - 1) {
                let i = y * tw + x, a = u[i - 1], b = u[i + 1], c = u[i - tw], e = u[i + tw]
                guard u[i] > 0, a > 0, b > 0, c > 0, e > 0 else { continue }
                let gx = f * (b - a) / (2 * u[i]), gy = f * (e - c) / (2 * u[i])   // how steeply it comes toward the camera, each way
                lit[i] = UInt8(max(0, min(255, 255 * (gx + gy + 1) / (1.7320508 * (gx * gx + gy * gy + 1).squareRoot()))))
            }
        }
        for (id, px) in [("depth", g), ("depthshade", lit)] { if let j = NDI.jpeg(px, tw, th) { thumb(id, j) } }
    }

    private static func jpeg(_ px: [UInt8], _ w: Int, _ h: Int) -> Data? {   // a grey picture as a JPEG
        let d = NSMutableData()
        guard let pr = CGDataProvider(data: Data(px) as CFData), let dest = CGImageDestinationCreateWithData(d as CFMutableData, "public.jpeg" as CFString, 1, nil),
              let im = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(),
                               provider: pr, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        CGImageDestinationAddImage(dest, im, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? d as Data : nil
    }

    static let closest: Float = 0.2   // DEPTH's near end: TrueDepth sees from about 20 cm, LiDAR about 25 (and 1/distance needs one)
    static let deepLong = 1920        // DEPTH's long side without its picture (Frames.enlarge): VIDEO's largest with depth (1440 x 1920)
    static let cardHz = 30.0, cardSide = 480   // the cards' pictures: 30 a second (15 looks choppy), their long side 480
    static func small(_ w: Int, _ h: Int) -> (Int, Int) {   // never bigger than the source: the page scales up smoothly, blocks it would not
        let s = min(cardSide, max(w, h))
        return w >= h ? (s, max(1, s * h / w)) : (max(1, s * w / h), s)
    }

    private func say(_ s: String) { if saidOnce.insert(s).inserted { said(s) } }
}
