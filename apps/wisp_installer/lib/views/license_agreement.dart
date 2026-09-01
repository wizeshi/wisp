import 'package:flutter/material.dart';
import 'package:wisp_installer/utils/license.dart';

class LicenseAgreementStep extends StatelessWidget {
  final bool isLicenseAccepted;
  final void Function(bool?) toggleLicenseAcceptance;
  final void Function() goToNextStep;

  const LicenseAgreementStep({
    super.key,
    required this.isLicenseAccepted,
    required this.toggleLicenseAcceptance,
    required this.goToNextStep,
  });

  @override
  Widget build(BuildContext context) {
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
                  'License Agreement',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Sorry for the legal jargon but, for legal reasons, I have to include this license agreement.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  licenseText,
                  style: TextStyle(fontSize: 14, color: Colors.white),
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    value: isLicenseAccepted,
                    onChanged: toggleLicenseAcceptance,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'I have read the license agreement and accept the terms and conditions',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: isLicenseAccepted ? goToNextStep : null,
                  child: Text(
                    'Continue',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
