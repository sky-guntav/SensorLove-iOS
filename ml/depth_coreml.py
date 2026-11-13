# SensorLove © 2026 Göktuğ Güntav. Free software under the GNU GPL v3 (LICENSE), with the additional terms in ADDITIONAL-TERMS.md.

"""Depth networks as Core ML models for DEPTH's DETAIL AI, for the Neural Engine, each checked against PyTorch.

  promptda  Prompt Depth Anything Small (PromptDA-S; code and weights Apache-2.0, github.com/DepthAnything/PromptDA): Depth
            Anything V2 Small with the depth sensor fed into its decoder (the "prompt"). Metres in, metres out:
              image                   in: the camera's picture, RGB, landscape as the camera stores it (Vision scales it)
              prompt                  in: the depth sensor's metres, Float16 1 x 1 x 240 x 320 (AVFoundation's LiDAR as it comes),
                                      no holes
              prompt_min, prompt_max  in: Float16 [1], the metres the prompt is scaled between. PromptDA takes each frame's own
                                      nearest and farthest, so one stray pixel rescales the whole frame; given here, they can be
                                      eased from frame to frame
              depth                   out: metres, GRAYSCALE_FLOAT16 (a OneComponent16Half pixel buffer), always between
                                      prompt_min and prompt_max (the network's last step is a sigmoid, stretched over that span)
  dav2      Depth Anything V2 Small (Apache-2.0), as Apple's Core ML conversion but not divided by each frame's own largest value,
            so the scale does not jump when the nearest thing changes:
              image                   in: as above
              depth                   out: relative 1/distance, GRAYSCALE_FLOAT16; its scale and shift are unknown (fit them to
                                      the sensor)

Each model has one size, a multiple of 14 each way: the encoder reads 1 + (width/14)(height/14) tokens. The encoder is laid out
for the Neural Engine as in Apple's Depth Anything V2 Small (machinelearning.apple.com/research/neural-engine-transformers):
(batch, channels, 1, tokens), 1 x 1 convolutions, each head on its own (einsum). Before it is converted, the network is checked
against transformers' own on PromptDA's example frame.

  python ml/depth_coreml.py build/m --model promptda --size 518x392   converts: the .mlpackage, report.md, model.mil, test.npz
                                                                       (Linux or macOS; torch, transformers, coremltools)
  python ml/depth_coreml.py build/m --check                            runs that model on its test frame and compares it with
                                                                       PyTorch (macOS; coremltools)
"""
import argparse, hashlib, io, os, sys, time, urllib.request
from collections import Counter
from pathlib import Path

import numpy as np

MODELS = {   # transformers' class, its Hugging Face repo at a fixed revision, model.safetensors' SHA-256 there (another file stops the run), the name
    'promptda': ('PromptDepthAnythingForDepthEstimation', 'depth-anything/prompt-depth-anything-vits-hf', '6f3768a5383d95a904ec00d2a7ca3bd186f8797e',
                 'b8dcec4ab96b47771addbfec2b7b410d801f472366b52fb5f20e2599e8d8c015', 'PromptDepthAnythingSmall'),
    'dav2': ('DepthAnythingForDepthEstimation', 'depth-anything/Depth-Anything-V2-Small-hf', '5426e4f0f36572d16453bbda7a8389317b1bef99',
             '3152477ce0d8d6978d76b995120de97cb5b928701fd0f817769f59e249a16b70', 'DepthAnythingV2Small'),
}
FRAME = 'https://raw.githubusercontent.com/DepthAnything/PromptDA/9161547ca7151e14fcc8f490ad3cc02fa9437483/assets/example_images/'   # an iPhone frame and its ARKit LiDAR in mm
PATCH, PW, PH = 14, 320, 240
MEAN, STD = (0.485, 0.456, 0.406), (0.229, 0.224, 0.225)   # both models' processors' (ImageNet's)


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def network(model, w, h):
    """transformers' network, and the same one with the encoder in the Neural Engine's layout (PromptDA: with the prompt's scale
    as inputs); the test frame; both answers for it"""
    import torch
    import torch.nn.functional as F
    import transformers
    from huggingface_hub import hf_hub_download
    from PIL import Image

    cls, repo, rev, weights, _ = MODELS[model]
    if sha256(hf_hub_download(repo, 'model.safetensors', revision=rev)) != weights:
        sys.exit(f'{repo} model.safetensors is not the file chosen: read what changed, then set its SHA-256')
    m = getattr(transformers, cls).from_pretrained(repo, revision=rev, dtype=torch.float32, attn_implementation='eager').eval()
    gw, gh = w // PATCH, h // PATCH

    def conv(lin, scale=1.0, norm=None):   # a Linear as the 1 x 1 convolution it is on (batch, channels, 1, tokens): its outputs
        weight, bias = lin.weight.data, lin.bias.data                           # times scale, the LayerNorm before it's gamma and beta in it
        if norm is not None:
            weight, bias = weight * norm.weight.data, bias + weight @ norm.bias.data
        s = torch.as_tensor(scale, dtype=torch.float32).expand(lin.out_features)
        c = torch.nn.Conv2d(lin.in_features, lin.out_features, 1)
        c.weight.data, c.bias.data = weight[:, :, None, None] * s[:, None, None, None], bias * s
        return c

    class Norm(torch.nn.Module):   # LayerNorm over the channels, coremltools' layer_norm(axes=[1]) as in Apple's; gamma and beta are
        def __init__(self, ln, affine=False):                              # in the convolutions after it, else a batch_norm of their own
            super().__init__()
            self.eps = ln.eps
            self.register_buffer('w', ln.weight.detach()[:, None, None].clone() if affine else torch.ones(1))
            self.register_buffer('b', ln.bias.detach()[:, None, None].clone() if affine else torch.zeros(1))

        def forward(self, x):
            z = x - x.mean(1, keepdim=True)
            return z * torch.rsqrt((z * z).mean(1, keepdim=True) + self.eps) * self.w + self.b

    class Block(torch.nn.Module):   # a Dinov2Layer
        def __init__(self, l):
            super().__init__()
            a = l.attention
            self.heads, self.norm1, self.norm2 = a.num_attention_heads, Norm(l.norm1), Norm(l.norm2)
            self.q, self.k, self.v = conv(a.q_proj, a.scaling, l.norm1), conv(a.k_proj, norm=l.norm1), conv(a.v_proj, norm=l.norm1)   # q carries 1/sqrt(64) (exact): no multiply per head
            self.o, self.fc1, self.fc2 = conv(a.o_proj, l.layer_scale1.lambda1.data), conv(l.mlp.fc1, norm=l.norm2), conv(l.mlp.fc2, l.layer_scale2.lambda1.data)

        def forward(self, x):
            n = self.norm1(x)
            q, k, v = self.q(n), self.k(n).transpose(1, 3), self.v(n)
            d, heads = self.q.out_channels // self.heads, []   # a number, not a traced shape
            for i in range(self.heads):   # ml-stable-diffusion's split_einsum: each head alone, keys along the channels, softmax over them
                hd = slice(i * d, (i + 1) * d)
                wt = torch.einsum('bchq,bkhc->bkhq', q[:, hd], k[:, :, :, hd]).softmax(1)
                heads.append(torch.einsum('bkhq,bchk->bchq', wt, v[:, hd]))
            x = x + self.o(torch.cat(heads, 1))
            return x + self.fc2(F.gelu(self.fc1(self.norm2(x))))

    class Net(torch.nn.Module):
        def __init__(self):
            super().__init__()
            b, e = m.backbone, m.backbone.embeddings
            self.patch, self.blocks, self.norm = e.patch_embeddings.projection, torch.nn.ModuleList(Block(l) for l in b.encoder.layer), Norm(b.layernorm, affine=True)
            self.taps, self.neck, self.head = b.config.out_indices, m.neck, m.head   # the encoder's layers (from 1) the decoder reads
            with torch.no_grad():   # the position embedding at this size, interpolated once as transformers does: a constant
                pos = e.interpolate_pos_encoding(torch.zeros(1, 1 + gh * gw, e.cls_token.shape[-1]), h, w).transpose(1, 2)[:, :, None]
            self.register_buffer('cls', e.cls_token.detach().transpose(1, 2)[:, :, None] + pos[..., :1])
            self.register_buffer('pos', pos[..., 1:].clone())
            self.register_buffer('mean', torch.tensor(MEAN)[None, :, None, None])
            self.register_buffer('scale', 1 / torch.tensor(STD)[None, :, None, None])

        def forward(self, image, *prompt):   # image 0 to 1 (the ImageType's 1/255); PromptDA: prompt, prompt_min, prompt_max in metres
            t = self.patch((image - self.mean) * self.scale).flatten(2)[:, :, None]   # (1, 384, 1, gh x gw), row by row
            t, feats = torch.cat((self.cls, t + self.pos), 3), []
            for i, blk in enumerate(self.blocks):
                t = blk(t)
                if i + 1 in self.taps:
                    feats.append(self.norm(t)[:, :, 0, 1:].reshape(1, -1, gh, gw))
            feats = [self.neck.convs[i](self.neck.reassemble_stage.layers[i](f)) for i, f in enumerate(feats)]
            if not prompt:   # relative 1/distance as the network gives it
                return self.head(self.neck.fusion_stage(feats), gh, gw)[:, None]
            prompt, lo, hi = prompt
            lo, span = lo.view(1, 1, 1, 1), (hi - lo).clamp(min=1e-3).view(1, 1, 1, 1)   # a flat wall: no division by 0
            depth = self.head(self.neck.fusion_stage(feats, prompt_depth=(prompt - lo) / span), gh, gw)
            return depth[:, None] * span + lo

    image = np.asarray(Image.open(io.BytesIO(fetch(FRAME + 'image.jpg'))).convert('RGB').resize((w, h), Image.BICUBIC))
    x = torch.from_numpy(image.copy()).permute(2, 0, 1)[None].float() / 255
    net, example, kw = Net().eval(), (x,), {}
    if model == 'promptda':
        lidar = torch.from_numpy(np.asarray(Image.open(io.BytesIO(fetch(FRAME + 'arkit_depth.png'))), np.float32) / 1000)[None, None]   # 256 x 192
        prompt = F.interpolate(lidar, (PH, PW), mode='bilinear', align_corners=False)
        example, kw = (x, prompt, prompt.amin().view(1), prompt.amax().view(1)), {'prompt_depth': prompt}   # transformers takes its own min and max
    with torch.no_grad():
        ref = m(pixel_values=(x - net.mean) * net.scale, **kw).predicted_depth[0].numpy()
        ours = net(*example)[0, 0].numpy()
    return net, example, image, ref, ours


def convert(out, model, w, h):
    import coremltools as ct
    import torch

    _, repo, rev, weights_sha, base = MODELS[model]
    name, prompted, gw, gh = f'{base}{w}x{h}F16', model == 'promptda', w // PATCH, h // PATCH
    net, example, image, ref, ours = network(model, w, h)
    gap = float(np.abs(ours - ref).max() / np.abs(ref).max())
    if gap > 1e-4:   # the rewrite must be transformers' network
        sys.exit(f'the Neural Engine layout is not transformers\' {repo}: {gap:.1e} of the largest value apart')
    with torch.no_grad():
        traced = torch.jit.trace(net, example)
    inputs = [ct.ImageType(name='image', shape=(1, 3, h, w), scale=1 / 255, color_layout=ct.colorlayout.RGB)]
    if prompted:
        inputs += [ct.TensorType(name='prompt', shape=(1, 1, PH, PW), dtype=np.float16),
                   ct.TensorType(name='prompt_min', shape=(1,), dtype=np.float16),
                   ct.TensorType(name='prompt_max', shape=(1,), dtype=np.float16)]
    ml = ct.convert(traced, inputs=inputs, outputs=[ct.ImageType(name='depth', color_layout=ct.colorlayout.GRAYSCALE_FLOAT16)],
                    convert_to='mlprogram', compute_precision=ct.precision.FLOAT16, minimum_deployment_target=ct.target.iOS17)
    ml.license, ml.version = 'Apache-2.0', f'{repo}@{rev[:7]}'
    ml.input_description['image'] = f'The picture, RGB {w} x {h}, landscape'
    if prompted:
        ml.short_description = 'Prompt Depth Anything Small (PromptDA-S): metric depth from a picture and a depth sensor\'s metres'
        ml.author = 'Haotong Lin et al. (PromptDA, github.com/DepthAnything/PromptDA); for Core ML: SensorLove (ml/depth_coreml.py)'
        ml.input_description['prompt'] = f'The depth sensor\'s distance in metres, {PW} x {PH}, lined up with the picture, no holes'
        ml.input_description['prompt_min'] = 'Metres the prompt is scaled from: its nearest (eased across frames)'
        ml.input_description['prompt_max'] = 'Metres the prompt is scaled to: its farthest (the depth stays between the two)'
        ml.output_description['depth'] = f'Distance in metres, {w} x {h}'
    else:
        ml.short_description = 'Depth Anything V2 Small: relative depth from a picture'
        ml.author = 'Lihe Yang et al. (Depth Anything V2, github.com/DepthAnything/Depth-Anything-V2); for Core ML: SensorLove (ml/depth_coreml.py)'
        ml.output_description['depth'] = f'Relative 1/distance, {w} x {h}, as the network gives it: scale and shift unknown'
    out.mkdir(parents=True, exist_ok=True)
    package = out / f'{name}.mlpackage'
    ml.save(str(package))

    spec, prog = ml.get_spec(), ml._mil_program
    (out / 'model.mil').write_text(str(prog), encoding='utf-8', newline='\n')
    ops = list(prog.functions['main'].operations)
    weights = sum(op.outputs[0].val.size for op in ops if op.op_type == 'const' and isinstance(op.outputs[0].val, np.ndarray) and op.outputs[0].val.size > 1)
    files = sorted(p for p in package.rglob('*') if p.is_file())
    bin_bytes = sum(p.stat().st_size for p in files if p.name == 'weight.bin')
    test = {'image': image, 'torch': ref, 'ours': ours}
    if prompted:
        test |= {'prompt': example[1].numpy(), 'prompt_min': example[2].numpy(), 'prompt_max': example[3].numpy()}
    np.savez_compressed(out / 'test.npz', **test)
    report = [f'# {name}', '',
              f'From `{repo}` at `{rev}` (model.safetensors SHA-256 `{weights_sha}`), coremltools {ct.__version__}, torch {torch.__version__}, '
              f'iOS 17 (spec {spec.specificationVersion}), FP16.', '',
              '| | name | type |', '|---|---|---|']
    report += [f'| in | `{d.name}` | {kind(d)} |' for d in spec.description.input]
    report += [f'| out | `{d.name}` | {kind(d)} |' for d in spec.description.output]
    report += ['', f'Tokens: 1 + {gw} x {gh} = {1 + gw * gh:,}. Weights: {weights:,} values, FP16, {bin_bytes:,} bytes in weight.bin. '
               f'Neural Engine layout against transformers on the test frame: at most {gap:.1e} of the largest value apart.', '',
               'Operations: ' + ', '.join(f'{k} {v}' for k, v in Counter(op.op_type for op in ops).most_common()), '',
               f'Files ({sum(p.stat().st_size for p in files):,} bytes):', '', '| bytes | SHA-256 | file |', '|---:|---|---|']
    report += [f'| {p.stat().st_size:,} | `{sha256(p)}` | {p.relative_to(out).as_posix()} |' for p in files]
    tell(out, report)
    if os.environ.get('GITHUB_OUTPUT'):   # the artifact's name
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as f:
            f.write(f'name={name}\n')


def kind(d):   # a model input's or output's type, in words
    t = d.type
    if t.WhichOneof('Type') == 'imageType':
        return f'image {t.imageType.width} x {t.imageType.height} {t.imageType.ColorSpace.Name(t.imageType.colorSpace)}'
    a = t.multiArrayType
    return f'{a.ArrayDataType.Name(a.dataType)} {list(a.shape)}'


def tell(out, lines, name='report.md'):   # into the folder, the log and the run's summary page
    text = '\n'.join(lines) + '\n'
    (out / name).write_text(text, encoding='utf-8', newline='\n')
    print(text)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as f:
            f.write(text)


def check(out):
    import coremltools as ct
    from PIL import Image

    package, t = next(out.glob('*.mlpackage')), np.load(out / 'test.npz')
    prompted, ref = 'prompt' in t.files, t['torch']
    feed = {'image': Image.fromarray(t['image'])}
    if prompted:
        feed |= {k: t[k].astype(np.float16) for k in ('prompt', 'prompt_min', 'prompt_max')}
    t0 = time.perf_counter()
    ml = ct.models.MLModel(str(package), compute_units=ct.ComputeUnit.CPU_ONLY)   # a virtual Mac has no Neural Engine (nor GPU)
    load, t0 = time.perf_counter() - t0, time.perf_counter()
    got = np.asarray(ml.predict(feed)['depth'], dtype=np.float32)
    once = time.perf_counter() - t0
    ok = got.shape == ref.shape and np.isfinite(got).all()
    e = np.abs(got - ref) if ok else np.full(1, np.inf)
    rel = e.mean() / np.abs(ref).mean()
    inside = not prompted or (ok and (got >= t['prompt_min'][0] - 0.01).all() and (got <= t['prompt_max'][0] + 0.01).all())
    v = (lambda x: f'{x * 1000:.2f} mm') if prompted else (lambda x: f'{x:.4g}')
    tell(out, [f'# {package.stem} on macOS (Core ML, CPU)', '',
               f'{got.shape[-1]} x {got.shape[0]}, loaded in {load:.1f} s, ran in {once * 1000:.0f} ms. Against PyTorch (transformers, FP32): '
               f'mean {v(e.mean())}, median {v(np.median(e))}, 99% within {v(np.percentile(e, 99))}, largest {v(e.max())}; '
               f'the mean difference is {rel * 100:.3f} % of the mean value (it ranges {v(ref.min())} to {v(ref.max())}).'
               + (f' Between prompt_min and prompt_max: {"yes" if inside else "NO"}.' if prompted else '')], 'check.md')
    if not ok or not inside or rel > 0.01:   # FP16 alone stays far below 1 %; a broken conversion is off by tens of %
        sys.exit(f'{package.stem}: Core ML\'s depth is not PyTorch\'s')


if __name__ == '__main__':
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument('out', type=Path, help='the folder for the model and its report')
    a.add_argument('--model', choices=MODELS, default='promptda')
    a.add_argument('--size', default='518x392', help='width x height, each a multiple of 14 (default: Apple\'s Depth Anything V2 Small\'s)')
    a.add_argument('--check', action='store_true', help='run the model in out on its test frame (macOS) instead of converting')
    args = a.parse_args()
    w, h = (int(n) for n in args.size.lower().split('x'))
    if w % PATCH or h % PATCH:
        a.error(f'--size {args.size}: each side must be a multiple of {PATCH}')
    check(args.out) if args.check else convert(args.out, args.model, w, h)
