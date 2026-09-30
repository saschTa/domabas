import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

Uint8List multipagePdf() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << /Font << /F1 7 0 R >> >> /Contents 4 0 R >>',
    _stream('BT /F1 20 Tf 20 350 Td (Orchard first page) Tj ET'),
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>',
    _stream('BT /F1 20 Tf 20 350 Td (Orchard second page) Tj ET'),
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(buffer.length);
    buffer.write('${index + 1} 0 obj\n${objects[index]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(buffer.toString()));
}

String _stream(String text) =>
    '<< /Length ${text.length} >>\nstream\n$text\nendstream';

Future<Uint8List> pngFixture() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
  canvas.drawRect(
    const ui.Rect.fromLTWH(16, 16, 608, 448),
    ui.Paint()..color = const ui.Color(0xff28654b),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(64, 64, 256, 128),
    ui.Paint()..color = const ui.Color(0xffe0eedf),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(32, 240, 576, 180),
    ui.Paint()..color = const ui.Color(0xffffffff),
  );
  final paragraph =
      (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 28, fontFamily: 'Arial'))
            ..pushStyle(ui.TextStyle(color: const ui.Color(0xff000000)))
            ..addText(
              'Invoice number 42\nDocument image test\nTotal amount 125 euros',
            ))
          .build();
  paragraph.layout(const ui.ParagraphConstraints(width: 540));
  canvas.drawParagraph(paragraph, const ui.Offset(48, 252));
  paragraph.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(640, 480);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Uint8List passwordPdf() => base64Decode(
  'JVBERi0xLjcKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFs0IDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL0ZvbnQgL1N1YnR5cGUgL1R5cGUxIC9CYXNlRm9udCAvSGVsdmV0aWNhID4+CmVuZG9iago0IDAgb2JqCjw8IC9UeXBlIC9QYWdlIC9QYXJlbnQgMiAwIFIgL01lZGlhQm94IFswIDAgMzAwIDIwMF0gL1Jlc291cmNlcyA8PCAvRm9udCA8PCAvRjEgMyAwIFIgPj4gPj4gL0NvbnRlbnRzIDUgMCBSID4+CmVuZG9iago1IDAgb2JqCjw8IC9MZW5ndGggNTYgPj4Kc3RyZWFtCj64uV/kWvs4emwpkiEFA8xfcPPJfo6E31qLFeLKpT061O7eMZzsUrmWROwyeG0P4iBdO4ee8cR/CmVuZHN0cmVhbQplbmRvYmoKNiAwIG9iago8PCAvRmlsdGVyIC9TdGFuZGFyZCAvViAxIC9SIDIgL0xlbmd0aCA0MCAvTyA8ZDMwMzAwYjAzNmIzMGFjYjJlZDY2YTM4MGU4ZDUxYmRjNGE2M2I1Y2EwYTU1NWQ3Mzc0ZTI5MzU5MTZhYWEwOD4gL1UgPGU3OGUyOWZjZWFhZGJmYTUwMThlNTU1N2Q5NmIyOGQzOGI3NTUzMDE1MTBmM2M4OWQ1MmY0Mjg2ODlhMzg4YzI+IC9QIC00ID4+CmVuZG9iagp4cmVmCjAgNwowMDAwMDAwMDAwIDY1NTM1IGYgCjAwMDAwMDAwMDkgMDAwMDAgbiAKMDAwMDAwMDA1OCAwMDAwMCBuIAowMDAwMDAwMTE1IDAwMDAwIG4gCjAwMDAwMDAxODUgMDAwMDAgbiAKMDAwMDAwMDMxMSAwMDAwMCBuIAowMDAwMDAwNDE3IDAwMDAwIG4gCnRyYWlsZXIKPDwgL1NpemUgNyAvUm9vdCAxIDAgUiAvRW5jcnlwdCA2IDAgUiAvSUQgWzxkY2Y2ZmRjZTBkMTZhNDlmYjJjNzRkMTRkMmUyZDM4ZD48ZGNmNmZkY2UwZDE2YTQ5ZmIyYzc0ZDE0ZDJlMmQzOGQ+XSA+PgpzdGFydHhyZWYKNjIzCiUlRU9GCg==',
);
