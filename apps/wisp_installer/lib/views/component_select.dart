import 'package:flutter/material.dart';
import 'package:wisp_installer/navigation/shell.dart';

class ComponentSelectStep extends StatelessWidget {
  void Function(InstallationComponent, bool?) toggleComponentSelection;
  bool Function(InstallationComponent) isComponentSelected;
  Future<void> Function() onStartInstallation;
  String detectedPlatform;
  bool isWindows;
  
  ComponentSelectStep({
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
          Column(
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
                title: 'YouTube Engines',
                description: 
                  'These components are used to extract streams from YouTube.\n'
                  'It is recommended to install at least one of these, as the app will not work without one of them installed.',
              ),

              buildComponentSelectionItem(
                context,
                title: 'NewPipeExtractor + JVM',
                description: 
                  "The NewPipeExtractor is a library that allows extracting YouTube stream URLs.\n"
                  "This component is a small program that runs this library, allowing for fast stream extraction.\n\n"
                  "It requires the Java Virtual Machine (JVM) to run, which is included in this component.",
                isSelected: isComponentSelected(InstallationComponent.NewPipeExtractor),
                onChanged: (value) {
                  toggleComponentSelection(InstallationComponent.NewPipeExtractor, value);
                },
                isRequired: false,
              ),
              buildComponentSelectionItem(
                context,
                title: 'YT-DLP + NodeJS',
                description: 
                  "YT-DLP is a command-line program for downloading videos from YouTube and other sites.\n"
                  "While slower, it supports automatic updates, which may prove useful if wisp doesn't get updated.\n\n"
                  "It requires a JS Runtime (Node.JS) to run, which is included in this component.",
                isSelected: isComponentSelected(InstallationComponent.YT_DLP),
                onChanged: (value) {
                  toggleComponentSelection(InstallationComponent.YT_DLP, value);
                },
                isRequired: false,
              ),
            ]
          ),
          Spacer(),
          Container(
            padding: EdgeInsets.only(bottom: 8.0),
            child: FilledButton(
              onPressed: showConfirmationDialog,
              child: Text('Continue', style: TextStyle(color: Colors.white)),
            )
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
