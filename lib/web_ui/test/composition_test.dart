// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:html' as html;

import 'package:test/bootstrap/browser.dart';
import 'package:test/test.dart';
import 'package:ui/src/engine/browser_detection.dart';

import 'package:ui/src/engine/dom.dart';
import 'package:ui/src/engine/initialization.dart';
import 'package:ui/src/engine/text_editing/composition_aware_mixin.dart';
import 'package:ui/src/engine/text_editing/input_type.dart';
import 'package:ui/src/engine/text_editing/text_editing.dart';

void main() {
  internalBootstrapBrowserTest(() => testMain);
}

class _MockWithCompositionAwareMixin with CompositionAwareMixin {
  // These variables should be equal to their counterparts in CompositionAwareMixin.
  // Separate so the counterparts in CompositionAwareMixin can be private.
  static const String _kCompositionUpdate = 'compositionupdate';
  static const String _kCompositionStart = 'compositionstart';
  static const String _kCompositionEnd = 'compositionend';
}

html.InputElement get _inputElement {
  return defaultTextEditingRoot.querySelectorAll('input').first as html.InputElement;
}

GloballyPositionedTextEditingStrategy _enableEditingStrategy({
    required bool deltaModel,
    void Function(EditingState?, TextEditingDeltaState?)? onChange,
  }) {
  final HybridTextEditing owner = HybridTextEditing();

  owner.configuration = InputConfiguration(inputType: EngineInputType.text, enableDeltaModel: deltaModel);

  final GloballyPositionedTextEditingStrategy editingStrategy =
      GloballyPositionedTextEditingStrategy(owner);

  owner.debugTextEditingStrategyOverride = editingStrategy;

  editingStrategy.enable(owner.configuration!, onChange: onChange ?? (_, __) {}, onAction: (_) {});
  return editingStrategy;
}

Future<void> testMain() async {
  await initializeEngine();

  const String fakeComposingText = 'ImComposingText';

  group('$CompositionAwareMixin', () {
    late TextEditingStrategy editingStrategy;

    setUp(() {
      editingStrategy = _enableEditingStrategy(deltaModel: false);
    });

    tearDown(() {
      editingStrategy.disable();
    });

    group('composition end', () {
      test('should reset composing text on handle composition end', () {
        final _MockWithCompositionAwareMixin mockWithCompositionAwareMixin =
            _MockWithCompositionAwareMixin();
        mockWithCompositionAwareMixin.composingText = fakeComposingText;
        mockWithCompositionAwareMixin.addCompositionEventHandlers(_inputElement
            as DomHTMLElement);

        _inputElement.dispatchEvent(html.Event(_MockWithCompositionAwareMixin._kCompositionEnd));

        expect(mockWithCompositionAwareMixin.composingText, null);
      });
    });

    group('composition start', () {
      test('should reset composing text on handle composition start', () {
        final _MockWithCompositionAwareMixin mockWithCompositionAwareMixin =
            _MockWithCompositionAwareMixin();
        mockWithCompositionAwareMixin.composingText = fakeComposingText;
        mockWithCompositionAwareMixin.addCompositionEventHandlers(_inputElement
            as DomHTMLElement);

        _inputElement.dispatchEvent(html.Event(_MockWithCompositionAwareMixin._kCompositionStart));

        expect(mockWithCompositionAwareMixin.composingText, null);
      });
    });

    group('composition update', () {
      test('should set composing text to event composing text', () {
        const String fakeEventText = 'IAmComposingThis';
        final _MockWithCompositionAwareMixin mockWithCompositionAwareMixin =
            _MockWithCompositionAwareMixin();
        mockWithCompositionAwareMixin.composingText = fakeComposingText;
        mockWithCompositionAwareMixin.addCompositionEventHandlers(_inputElement
            as DomHTMLElement);

        _inputElement.dispatchEvent(html.CompositionEvent(
            _MockWithCompositionAwareMixin._kCompositionUpdate,
            data: fakeEventText
        ));

        expect(mockWithCompositionAwareMixin.composingText, fakeEventText);
      });
    });

    group('determine composition state', () {
      test('should return new composition state if valid new composition', () {
        const int baseOffset = 100;
        const String composingText = 'composeMe';

        final EditingState editingState = EditingState(
          extentOffset: baseOffset,
          text: 'testing',
          baseOffset: baseOffset,
        );

        final _MockWithCompositionAwareMixin mockWithCompositionAwareMixin =
            _MockWithCompositionAwareMixin();
        mockWithCompositionAwareMixin.composingText = composingText;

        const int expectedComposingBase = baseOffset - composingText.length;

        expect(
            mockWithCompositionAwareMixin.determineCompositionState(editingState),
            editingState.copyWith(
                composingBaseOffset: expectedComposingBase,
                composingExtentOffset: expectedComposingBase + composingText.length));
      });
    });
  });

  group('composing range', () {
    late GloballyPositionedTextEditingStrategy editingStrategy;

    setUp(() {
      editingStrategy = _enableEditingStrategy(deltaModel: false);
    });

    tearDown(() {
      editingStrategy.disable();
    });

    test('should be [0, compostionStrLength] on new composition', () {
      const String composingText = 'hi';

      _inputElement.dispatchEvent(html.CompositionEvent(_MockWithCompositionAwareMixin._kCompositionUpdate, data: composingText));

      // Set the selection text.
      _inputElement.value = composingText;
      _inputElement.dispatchEvent(html.Event.eventType('Event', 'input'));

      expect(
          editingStrategy.lastEditingState,
          isA<EditingState>()
              .having((EditingState editingState) => editingState.composingBaseOffset,
                  'composingBaseOffset', 0)
              .having((EditingState editingState) => editingState.composingExtentOffset,
                  'composingExtentOffset', composingText.length));
    });

    test(
        'should be [beforeComposingText - composingText, compostionStrLength] on composition in the middle of text',
        () {
      const String composingText = 'hi';
      const String beforeComposingText = 'beforeComposingText';
      const String afterComposingText = 'afterComposingText';

      // Type in the text box, then move cursor to the middle.
      _inputElement.value = '$beforeComposingText$afterComposingText';
      _inputElement.setSelectionRange(beforeComposingText.length, beforeComposingText.length);

      _inputElement.dispatchEvent(html.CompositionEvent(
          _MockWithCompositionAwareMixin._kCompositionUpdate,
          data: composingText
      ));

      // Flush editing state (since we did not compositionend).
      _inputElement.dispatchEvent(html.Event.eventType('Event', 'input'));

      expect(
          editingStrategy.lastEditingState,
          isA<EditingState>()
              .having((EditingState editingState) => editingState.composingBaseOffset!,
                  'composingBaseOffset', beforeComposingText.length - composingText.length)
              .having((EditingState editingState) => editingState.composingExtentOffset,
                  'composingExtentOffset', beforeComposingText.length));
    });
  });

  group('Text Editing Delta Model', () {
    late GloballyPositionedTextEditingStrategy editingStrategy;

    final StreamController<TextEditingDeltaState?> deltaStream =
        StreamController<TextEditingDeltaState?>.broadcast();

    setUp(() {
        editingStrategy = _enableEditingStrategy(
          deltaModel: true,
          onChange: (_, TextEditingDeltaState? deltaState) => deltaStream.add(deltaState)
        );
    });

    tearDown(() {
      editingStrategy.disable();
    });

    test('should have newly entered composing characters', () async {
      const String newComposingText = 'n';

      editingStrategy.setEditingState(EditingState(text: newComposingText, baseOffset: 1, extentOffset: 1));

      final Future<dynamic> containExpect = expectLater(
          deltaStream.stream.first,
          completion(isA<TextEditingDeltaState>()
            .having((TextEditingDeltaState deltaState) => deltaState.composingOffset, 'composingOffset', 0)
            .having((TextEditingDeltaState deltaState) => deltaState.composingExtent, 'composingExtent', newComposingText.length)
          ));


      _inputElement.dispatchEvent(html.CompositionEvent(
          _MockWithCompositionAwareMixin._kCompositionUpdate,
          data: newComposingText));

      await containExpect;
    });

    test('should emit changed composition', () async {
      const String newComposingCharsInOrder = 'hiCompose';

      for (int currCharIndex = 0; currCharIndex < newComposingCharsInOrder.length; currCharIndex++) {
        final String currComposingSubstr = newComposingCharsInOrder.substring(0, currCharIndex + 1);

        editingStrategy.setEditingState(
          EditingState(text: currComposingSubstr, baseOffset: currCharIndex + 1, extentOffset: currCharIndex + 1)
        );

        final Future<dynamic> containExpect = expectLater(
          deltaStream.stream.first,
          completion(isA<TextEditingDeltaState>()
            .having((TextEditingDeltaState deltaState) => deltaState.composingOffset, 'composingOffset', 0)
            .having((TextEditingDeltaState deltaState) => deltaState.composingExtent, 'composingExtent', currCharIndex + 1)
        ));

        _inputElement.dispatchEvent(html.CompositionEvent(
          _MockWithCompositionAwareMixin._kCompositionUpdate,
          data: currComposingSubstr));

        await containExpect;
      }
    },
    // TODO(antholeole): This test fails on Firefox because of how it orders events;
    // it's likely that this will be fixed by https://github.com/flutter/flutter/issues/105243.
    // Until the refactor gets merged, this test should run on all other browsers to prevent
    // regressions in the meantime.
    skip: browserEngine == BrowserEngine.firefox);
  });
}
