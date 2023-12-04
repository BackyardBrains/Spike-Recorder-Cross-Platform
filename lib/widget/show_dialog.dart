import 'package:flutter/material.dart';
import 'package:native_add/model/model.dart';
import 'package:spikerbox_architecture/widget/custom_button.dart';

class CustomDialogWidget extends StatefulWidget {
  CustomDialogWidget({
    super.key,
    required this.sampleRateController,
    required this.cutOffController,
    required this.title,
  });

  final TextEditingController sampleRateController;
  final TextEditingController cutOffController;
  final String title;

  @override
  State<CustomDialogWidget> createState() => _CustomDialogWidgetState();
}

class _CustomDialogWidgetState extends State<CustomDialogWidget> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      actionsPadding: const EdgeInsets.all(12),
      title: Text(widget.title),
      actions: [
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: widget.sampleRateController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sample Rate'),
                validator: (value) {
                  if (value!.isEmpty) {
                    return 'Please enter a sample Rate';
                  }
                  final channelCount = int.tryParse(value);
                  if (channelCount == null || channelCount <= 0) {
                    return 'Sample rate must be a positive';
                  }
                  return null; // Validation passed
                },
              ),
              TextFormField(
                controller: widget.cutOffController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'CutOff  frequency'),
                validator: (value) {
                  if (value!.isEmpty) {
                    return 'Please enter a CutOff frequency';
                  }
                  final channelCount = int.tryParse(value);
                  if (channelCount == null || channelCount <= 0) {
                    return 'CutOff frequency must be a positive integer';
                  }
                  return null; // Validation passed
                },
              ),
              CustomButton(
                onTap: () {
                  if (_formKey.currentState!.validate()) {
                    FilterSettings filterBase = FilterSettings(
                        cutOff: int.parse(widget.cutOffController.text),
                        sampleRate:
                            int.parse(widget.sampleRateController.text));

                    Navigator.of(context).pop(filterBase);
                  } // Close the dialog
                },
                childWidget: const Text('Done'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
