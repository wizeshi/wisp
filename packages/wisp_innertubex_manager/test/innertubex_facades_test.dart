import 'package:flutter_test/flutter_test.dart';
import 'package:wisp_innertubex_manager/wisp_innertubex_manager.dart';
import 'package:wisp_shared/models/youtube_engine.dart';

void main() {
  group('InnerTubeX Engine and Facades', () {
    test('WispInnerTubeXEngine singleton and properties', () {
      final engine1 = WispInnerTubeXEngine();
      final engine2 = WispInnerTubeXEngine.instance;

      expect(identical(engine1, engine2), true);
      expect(engine1.name, 'InnerTubeX');
      expect(engine1.state, YoutubeEngineState.uninitialized);
    });

    test('WispInnerTubeXMetadataExtractor singleton', () {
      final extractor1 = WispInnerTubeXMetadataExtractor();
      final extractor2 = WispInnerTubeXMetadataExtractor.instance;

      expect(identical(extractor1, extractor2), true);
    });
  });
}

