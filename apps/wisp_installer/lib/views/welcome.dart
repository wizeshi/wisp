import 'package:flutter/material.dart';

class WelcomeStep extends StatelessWidget {
  final VoidCallback goToNextStep;

  const WelcomeStep({super.key, required this.goToNextStep});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 8,
      children: [
        Text(
          'Install wisp',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Text(
          textAlign: TextAlign.center,
          'This executable will guide you through the installation of the wisp app \n'
          'To continue, either press the button on the top right, or the button below! \n'
        ),
        FilledButton(
          onPressed: goToNextStep, 
          child: Text('Proceed with installation', style: TextStyle(color: Colors.white)),
        )
      ]
    );
  }
}