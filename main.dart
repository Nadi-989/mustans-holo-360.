import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MustansHoloApp());
}

class MustansHoloApp extends StatelessWidget {
  const MustansHoloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mustans Holo 360',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const EditorPage(),
    );
  }
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage>
    with SingleTickerProviderStateMixin {
  static const double _captureLogicalSize = 512;

  final ImagePicker _picker = ImagePicker();
  final GlobalKey _captureKey = GlobalKey();
  final TextEditingController _watermarkController =
      TextEditingController(text: 'Mustans_Holo');

  Uint8List? _originalBytes;
  Uint8List? _processedBytes;
  bool _isBusy = false;
  bool _autoRotate = true;
  double _manualAngle = 0;
  double _exportAngle = 0;
  String _status = '«Œ — ’Ê—… ··»œ¡';

  int _outputSize = 2048;
  int _fps = 24;
  int _durationSeconds = 6;

  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _watermarkController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) {
      return;
    }

    final Uint8List bytes = await file.readAsBytes();
    setState(() {
      _originalBytes = bytes;
      _processedBytes = null;
      _status = ' „ «Œ Ì«— «·’Ê—…. «÷€ÿ „⁄«·Ã….';
    });
  }

  Future<void> _processImage() async {
    if (_originalBytes == null) {
      setState(() {
        _status = '·«  ÊÃœ ’Ê—… Õ«·Ì«.';
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Ã«—Ì „⁄«·Ã… «·’Ê—…...';
    });

    try {
      final img.Image? source = img.decodeImage(_originalBytes!);
      if (source == null) {
        setState(() {
          _status = '›‘· ﬁ—«¡… «·’Ê—….';
        });
        return;
      }

      final int side = math.max(source.width, source.height);
      final img.Image canvas = img.Image(width: side, height: side);
      img.fill(canvas, color: img.ColorRgb8(0, 0, 0));

      final int fitW = (source.width / math.max(source.width, source.height) * side)
          .round();
      final int fitH =
          (source.height / math.max(source.width, source.height) * side).round();

      final img.Image fitted = img.copyResize(
        source,
        width: fitW,
        height: fitH,
        interpolation: img.Interpolation.average,
      );

      final int dstX = ((side - fitW) / 2).round();
      final int dstY = ((side - fitH) / 2).round();
      img.compositeImage(canvas, fitted, dstX: dstX, dstY: dstY);

      final String watermark = _watermarkController.text.trim().isEmpty
          ? 'Mustans_Holo'
          : _watermarkController.text.trim();

      img.drawString(
        canvas,
        watermark,
        font: img.arial48,
        x: math.max(12, side - (watermark.length * 26) - 28),
        y: side - 70,
        color: img.ColorRgb8(255, 255, 255),
      );

      final Uint8List result = Uint8List.fromList(img.encodePng(canvas));

      setState(() {
        _processedBytes = result;
        _status = ' „  «·„⁄«·Ã… »‰Ã«Õ.';
      });
    } catch (e) {
      setState(() {
        _status = 'ÕœÀ Œÿ√ √À‰«¡ «·„⁄«·Ã…: $e';
      });
    } finally {
      setState(() {
        _isBusy = false;
      });
    }
  }

  Future<void> _saveProcessedImage() async {
    if (_processedBytes == null) {
      setState(() {
        _status = '·«  ÊÃœ ’Ê—… „⁄«·Ã… ··Õ›Ÿ.';
      });
      return;
    }

    try {
      final Directory dir = await getTemporaryDirectory();
      final String path =
          '${dir.path}/mustans_holo_${DateTime.now().millisecondsSinceEpoch}.png';
      final File out = File(path);
      await out.writeAsBytes(_processedBytes!);
      await Gal.putImage(path);

      setState(() {
        _status = ' „ Õ›Ÿ «·’Ê—… ›Ì «·„⁄—÷.';
      });
    } catch (e) {
      setState(() {
        _status = ' ⁄–— «·Õ›Ÿ: $e';
      });
    }
  }

  Widget _buildHoloFrame(Uint8List bytes, double angle) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..rotateY(angle),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<Uint8List> _captureCurrentFramePng() async {
    final RenderRepaintBoundary boundary =
        _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;

    final double pixelRatio = _outputSize / _captureLogicalSize;
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception(' ⁄–— «· ﬁ«ÿ «·›—Ì„.');
    }
    return byteData.buffer.asUint8List();
  }

  Future<List<File>> _renderFrames(Directory folder) async {
    final Uint8List? display = _processedBytes ?? _originalBytes;
    if (display == null) {
      throw Exception('«Œ — ’Ê—… √Ê·«.');
    }

    final int frameCount = (_fps * _durationSeconds).clamp(24, 720);
    final List<File> files = [];

    for (int i = 0; i < frameCount; i++) {
      final double angle = (2 * math.pi * i) / frameCount;
      setState(() {
        _exportAngle = angle;
        _status = 'Ã«—Ú  Ê·Ìœ «·›—Ì„ ${i + 1} „‰ $frameCount';
      });

      await Future.delayed(const Duration(milliseconds: 12));
      await WidgetsBinding.instance.endOfFrame;

      final Uint8List png = await _captureCurrentFramePng();
      final String framePath = '${folder.path}/frame_${i.toString().padLeft(4, '0')}.png';
      final File frameFile = File(framePath);
      await frameFile.writeAsBytes(png);
      files.add(frameFile);
    }

    return files;
  }

  Future<void> _exportGif() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isBusy = true;
      _status = '»œ¡  ’œÌ— GIF...';
    });

    try {
      final Directory tmp = await getTemporaryDirectory();
      final Directory framesDir =
          Directory('${tmp.path}/holo_frames_gif_${DateTime.now().millisecondsSinceEpoch}');
      await framesDir.create(recursive: true);

      final List<File> frames = await _renderFrames(framesDir);

      final animation = img.Animation();
      for (final File frame in frames) {
        final img.Image? decoded = img.decodePng(await frame.readAsBytes());
        if (decoded != null) {
          animation.addFrame(decoded, duration: (1000 / _fps).round());
        }
      }

      final List<int> gifBytes = img.encodeGifAnimation(animation);
      final Directory docs = await getApplicationDocumentsDirectory();
      final String outPath =
          '${docs.path}/mustans_holo_${DateTime.now().millisecondsSinceEpoch}.gif';
      final File out = File(outPath);
      await out.writeAsBytes(gifBytes);

      await Gal.putImage(outPath);

      setState(() {
        _status = ' „  ’œÌ— GIF ÊÕ›ŸÂ ›Ì «·„⁄—÷.';
      });
    } catch (e) {
      setState(() {
        _status = '›‘·  ’œÌ— GIF: $e';
      });
    } finally {
      setState(() {
        _isBusy = false;
      });
    }
  }

  Future<void> _exportMp4() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isBusy = true;
      _status = '»œ¡  ’œÌ— MP4...';
    });

    try {
      final Directory tmp = await getTemporaryDirectory();
      final Directory framesDir =
          Directory('${tmp.path}/holo_frames_mp4_${DateTime.now().millisecondsSinceEpoch}');
      await framesDir.create(recursive: true);

      await _renderFrames(framesDir);

      final Directory docs = await getApplicationDocumentsDirectory();
      final String outPath =
          '${docs.path}/mustans_holo_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final String inputPattern = '${framesDir.path}/frame_%04d.png'.replaceAll('\\', '/');
      final String outputPath = outPath.replaceAll('\\', '/');

      final String cmd =
          '-y -framerate $_fps -i "$inputPattern" -c:v libx264 -pix_fmt yuv420p -crf 18 "$outputPath"';

      final session = await FFmpegKit.execute(cmd);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        await Gal.putVideo(outPath);
        setState(() {
          _status = ' „  ’œÌ— ›ÌœÌÊ MP4 ÊÕ›ŸÂ ›Ì «·„⁄—÷.';
        });
      } else {
        final logs = await session.getAllLogsAsString();
        throw Exception('FFmpeg failed: $logs');
      }
    } catch (e) {
      setState(() {
        _status = '›‘·  ’œÌ— MP4: $e';
      });
    } finally {
      setState(() {
        _isBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? display = _processedBytes ?? _originalBytes;

    return Scaffold(
      appBar: AppBar(title: const Text('Mustans Holo 360 3D')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: display == null
                      ? const Text('·«  ÊÃœ ’Ê—…')
                      : AnimatedBuilder(
                          animation: _rotationController,
                          builder: (context, child) {
                            final double angle = _autoRotate
                                ? _rotationController.value * 2 * math.pi
                                : _manualAngle;
                            return _buildHoloFrame(display, angle);
                          },
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _watermarkController,
                decoration: const InputDecoration(
                  labelText: '«·‰’ «·„«∆Ì',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _outputSize,
                      decoration: const InputDecoration(
                        labelText: 'œﬁ… «·≈Œ—«Ã',
                        border: OutlineInputBorder(),
                      ),
                      items: const [1024, 2048, 3072]
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text('$v x $v'),
                            ),
                          )
                          .toList(),
                      onChanged: _isBusy
                          ? null
                          : (v) {
                              if (v == null) {
                                return;
                              }
                              setState(() {
                                _outputSize = v;
                              });
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _fps,
                      decoration: const InputDecoration(
                        labelText: 'FPS',
                        border: OutlineInputBorder(),
                      ),
                      items: const [18, 24, 30]
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text('$v'),
                            ),
                          )
                          .toList(),
                      onChanged: _isBusy
                          ? null
                          : (v) {
                              if (v == null) {
                                return;
                              }
                              setState(() {
                                _fps = v;
                              });
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(' œÊÌ— 360∞  ·ﬁ«∆Ì (3D Preview)'),
                value: _autoRotate,
                onChanged: _isBusy
                    ? null
                    : (value) {
                        setState(() {
                          _autoRotate = value;
                        });
                      },
              ),
              Slider(
                value: _manualAngle,
                min: 0,
                max: 2 * math.pi,
                onChanged: (_autoRotate || _isBusy)
                    ? null
                    : (value) {
                        setState(() {
                          _manualAngle = value;
                        });
                      },
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _isBusy ? null : _pickImage,
                      child: const Text('«Œ Ì«— ’Ê—…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isBusy ? null : _processImage,
                      child: const Text('„⁄«·Ã…'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isBusy ? null : _saveProcessedImage,
                      child: const Text('Õ›Ÿ PNG'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: _isBusy ? null : _exportGif,
                      child: const Text(' ’œÌ— GIF'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: _isBusy ? null : _exportMp4,
                      child: const Text(' ’œÌ— MP4'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _status,
                style: const TextStyle(fontSize: 13),
                textAlign: TextAlign.center,
              ),

              if (display != null)
                SizedBox(
                  width: 1,
                  height: 1,
                  child: RepaintBoundary(
                    key: _captureKey,
                    child: SizedBox(
                      width: _captureLogicalSize,
                      height: _captureLogicalSize,
                      child: _buildHoloFrame(display, _exportAngle),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
