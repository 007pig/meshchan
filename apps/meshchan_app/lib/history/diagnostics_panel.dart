import 'dart:async';

import 'package:flutter/material.dart';

import '../drafts/quit_coordinator.dart';
import '../diagnostics/view.dart';
import 'view.dart';

class DiagnosticsPanel extends StatelessWidget {
  const DiagnosticsPanel({
    super.key,
    required this.coordinator,
    required this.chooseDevice,
  });
  final DraftQuitCoordinator coordinator;
  final VoidCallback chooseDevice;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: coordinator.history,
    builder: (context, _) {
      final h = coordinator.history;
      void show(bool value, {String? runId}) {
        if (coordinator.diagnostics.deferChangeForComposition()) return;
        if (h.composing) {
          h.allowChange();
          return;
        }
        h.show(value);
        if (value) {
          if (runId != null) {
            unawaited(h.select(runId));
          } else {
            unawaited(h.enter());
          }
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TextButton(
                onPressed: () => show(false),
                child: Text(h.visible ? 'Run' : 'Run • selected'),
              ),
              TextButton(
                onPressed: () => show(true),
                child: Text(h.visible ? 'History • selected' : 'History'),
              ),
            ],
          ),
          Expanded(
            child: h.visible
                ? HistoryView(model: h, output: coordinator.output)
                : Column(
                    children: [
                      ListenableBuilder(
                        listenable: coordinator.diagnostics,
                        builder: (context, _) {
                          final id = coordinator.diagnostics.attempt?.runId;
                          return id == null
                              ? const SizedBox.shrink()
                              : TextButton(
                                  onPressed: () => show(true, runId: id),
                                  child: const Text(
                                    'Read this run from history',
                                  ),
                                );
                        },
                      ),
                      Expanded(
                        child: DiagnosticsView(
                          model: coordinator.diagnostics,
                          profiles: coordinator.profiles,
                          chooseDevice: chooseDevice,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      );
    },
  );
}
