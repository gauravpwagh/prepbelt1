import 'package:prep_core/prep_core.dart';

String sourceTypeLabel(SourceType t) => switch (t) {
      SourceType.pdf => 'PDF',
      SourceType.book => 'Printed book',
      SourceType.web => 'Web page',
      SourceType.aiChat => 'AI chat',
      SourceType.video => 'Video',
      SourceType.notes => 'Notes',
      SourceType.lecture => 'Lecture',
      SourceType.app => 'App',
      SourceType.otherDevice => 'On another device',
    };

String taskKindLabel(TaskKind k) => switch (k) {
      TaskKind.reading => 'Reading',
      TaskKind.pyq => 'PYQ practice',
      TaskKind.other => 'Other',
    };
