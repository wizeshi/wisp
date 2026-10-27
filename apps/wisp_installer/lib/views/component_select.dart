import 'package:flutter/material.dart';
import 'package:wisp_installer/navigation/shell.dart';

class ComponentSelectStep extends StatelessWidget {
  final void Function(InstallationComponent, bool?) toggleComponentSelection;
  final bool Function(InstallationComponent) isComponentSelected;
  final Future<void> Function() onStartInstallation;
  final String detectedPlatform;
  final bool isWindows;
  
  const ComponentSelectStep({
    super.key, 
    required this.toggleComponentSelection,
    required this.isComponentSelected,
    required this.onStartInstallation,
    required this.detectedPlatform,
    required this.isWindows,
  });

  @override
  Widget build(BuildContext context) {
    showConfirmationDialog() {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Confirm Component Selection'),
            content: Text('Are you sure you want to continue with the selected components?'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
                child: Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onStartInstallation();
                },
                child: Text('Continue', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(12, (28.0 + 12.0 + 12.0), 12, 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        spacing: 8,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Column(
              children: [
                Text(
                  'Component Selection',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  textAlign: TextAlign.center,
                  'This step allows you to select which components you wish to install.\n'
                  'Click the information icon next to each to view more details about it.\n'
                  "Don't worry, you can always install these later, in the settings of the app.",
                  style: TextStyle(fontSize: 12, color: Colors.grey[400])
                ),
              ]
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  buildComponentSelectionItem(
                    context, 
                    title: 'Core ($detectedPlatform)',
                    description: "This is the app's core functionality. Not optional.",
                    isSelected: true,
                    onChanged: (value) {
                      toggleComponentSelection(InstallationComponent.Core, value);
                    },
                    isRequired: true,
                  ),
                  if (isWindows)
                    buildComponentSelectionItem(
                      context,
                      title: 'Edge WebView2',
                      description:
                          "Microsoft Edge's WebView2 Runtime.\nWon't install if already detected on your system.",
                      isSelected: true,
                      onChanged: (value) {
                        toggleComponentSelection(
                          InstallationComponent.EdgeWebView2,
                          value,
                        );
                      },
                      isRequired: true,
                    ),

                  buildComponentSelectionSection(
                    title: 'Runtimes & YouTube Engines',
                    description: 
                      'These components provide the background runtimes and audio engines for streaming from YouTube.\n'
                      'It is recommended to install at least one engine, as the app will not stream YouTube audio without one.',
                  ),

                  buildComponentSelectionItem(
                    context,
                    title: 'Java Runtime (JVM 21)',
                    description: 
                      "Eclipse Adoptium OpenJDK 21 JRE.\n"
                      "Required to run JVM-based engines like NewPipeExtractor.\n"
                      "Automatically required when any JVM-dependent engine is selected.",
                    isSelected: isComponentSelected(InstallationComponent.JavaRuntime),
                    onChanged: (value) {
                      toggleComponentSelection(InstallationComponent.JavaRuntime, value);
                    },
                    isRequired: isComponentSelected(InstallationComponent.NewPipeExtractor) ||
        isComponentSelected(InstallationComponent.InnerTubeX),
                  ),

                  buildComponentSelectionItem(
                    context,
                    title: 'NewPipeExtractor',
                    description: 
                      "The NewPipeExtractor is a library that allows extracting YouTube stream URLs.\n"
                      "This component runs the library in the background, allowing for fast stream extraction.\n\n"
                      "Requires the Java Virtual Machine (JVM 21) to run.",
                    isSelected: isComponentSelected(InstallationComponent.NewPipeExtractor),
                    onChanged: (value) {
                      toggleComponentSelection(InstallationComponent.NewPipeExtractor, value);
                    },
                    isRequired: false,
                  ),

                  buildComponentSelectionItem(
                    context,
                    title: 'InnerTubeX',
                    description: 
                      "Metrolist InnerTubeX streaming engine and metadata extractor.\n"
                      "Supports SABR/UMP audio streams, rich metadata, and user authentication.\n\n"
                      "Requires the Java Virtual Machine (JVM 21) to run.",
                    isSelected: isComponentSelected(InstallationComponent.InnerTubeX),
                    onChanged: (value) {
                      toggleComponentSelection(InstallationComponent.InnerTubeX, value);
                    },
                    isRequired: false,
                  ),

                  buildComponentSelectionItem(
                    context,
                    title: 'YT-DLP + Node.js',
                    description: 
                      "YT-DLP is a command-line program for downloading videos from YouTube and other sites.\n"
                      "While slower, it supports automatic updates, which may prove useful if wisp doesn't get updated.\n\n"
                      "It requires a JS Runtime (Node.js) to run, which is included in this component.",
                    isSelected: isComponentSelected(InstallationComponent.YT_DLP),
                    onChanged: (value) {
                      toggleComponentSelection(InstallationComponent.YT_DLP, value);
                    },
                    isRequired: false,
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
            child: FilledButton(
              onPressed: showConfirmationDialog,
              child: const Text('Continue', style: TextStyle(color: Colors.white)),
            ),
          )
        ]
      )
    );
  }

  Widget buildComponentSelectionSection({
    required String title,
    required String description,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Row(
        spacing: 12, 
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              Text(
                description,
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
            ]
          ),
          Expanded(
            child: Divider(color: Colors.grey[700], thickness: 1, height: 1)
          )
        ]
      )
    );
  }

  Widget buildComponentSelectionItem(BuildContext context, {
    required String title, 
    required String description, 
    required bool isSelected, 
    required ValueChanged<bool?> onChanged,
    bool isRequired = false,
  }) {
    return Container(
      padding: EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            onChanged: onChanged,
            activeColor: isRequired ? Colors.grey : Theme.of(context).colorScheme.primary,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.info_outline, color: Colors.grey[400]),
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text(title),
                    content: Text(description),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: Text('Close'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
