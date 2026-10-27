// Plan item 103: export with progress, wipe, import, and compare the belts.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prep_core/prep_core.dart';
import 'package:prepbelt/core/providers.dart';

import '../test/application/app_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('export with progress → fresh phone → same belts', (tester) async {
    final a = Fixture();
    final ca = containerFor(a);
    await a.seedTree();
    final exam = await ca.read(saveExamProvider).create('MPSC', day0.plusDays(90), {'sub1'});
    await a.writer.writeFirstStudy('st1', 30);
    await a.writer.writeReview('st1', Grade.solid, 8);
    final json = (await ca.read(examExporterProvider)
            .build(exam, PackageMode.progress, includeNotes: true))
        .encode();

    final b = Fixture();
    final cb = containerFor(b);
    final importer = cb.read(examImporterProvider);
    await importer.import(await importer.preview(ExamPackage.decode(json)),
        examName: 'MPSC', examDate: day0.plusDays(90));
    expect(await b.db.itemStateDao.all(), await a.db.itemStateDao.all());

    ca.dispose();
    cb.dispose();
    await a.close();
    await b.close();
  });
}
