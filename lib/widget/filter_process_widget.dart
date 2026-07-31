import 'package:flutter/material.dart';
import 'package:native_add/model/filterbase_setting.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/models/microphone_stream/microphone_stream_check.dart';
import 'package:spikerbox_architecture/provider/data_type_status.dart';

class FilterProcessWidget extends StatefulWidget {
  const FilterProcessWidget({
    super.key,
    required this.onHighPassFilterSetup,
    required this.onLowPassFilterSetup,
    required this.onSampleChange,
    required this.isMicrophoneEnable,
  });

  final Function(bool) isMicrophoneEnable;
  final Function(bool) onSampleChange;
  final Function(FilterSetup) onHighPassFilterSetup;
  final Function(FilterSetup) onLowPassFilterSetup;

  @override
  State<FilterProcessWidget> createState() => _FilterProcessWidgetState();
}

class _FilterProcessWidgetState extends State<FilterProcessWidget> {
  MicrophoneUtil microphoneUtil = MicrophoneUtil();
  bool _isSampleDataOn = false;
  bool _isMicrophoneEnable = false;
  final TextEditingController _lowSampleRateController =
      TextEditingController();
  final TextEditingController _lowCutOffController = TextEditingController();
  final TextEditingController _highSampleRateController =
      TextEditingController();
  final TextEditingController _highCutOffController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _lowCutOffController.dispose();
    _lowSampleRateController.dispose();
    _highCutOffController.dispose();
    _highSampleRateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DataStatusProvider>(
        builder: (context, dataStatus, snapshot) {
      return Column(
        children: [
          // Row(
          //   children: [
          //     WhiteColorCheckBox(
          //       valueStatus: dataStatus.isSampleDataOn,
          //       onChanged: (value) {
          //         setState(() {
          //           _isSampleDataOn = value ?? false;
          //           if (_isSampleDataOn && _isMicrophoneEnable) {
          //             _isMicrophoneEnable = false;
          //             widget.isMicrophoneEnable(_isMicrophoneEnable);
          //           }
          //         });
          //         print("dummySamplingRate : $dummySamplingRate");
          //         Provider.of<SampleRateProvider>(context, listen: false).setSampleRate(dummySamplingRate);
          //         widget.onSampleChange(_isSampleDataOn);
          //       },
          //     ),
          //     Text(
          //       "Sample Data ",
          //       style: SoftwareTextStyle().kWtMediumTextStyle,
          //     )
          //   ],
          // ),
          const SizedBox(height: 10),
          // CustomButton(
          //   childWidget: const Text("Check audio on web"),
          //   onTap: () async {},
          // ),
          Row(
            children: [
              // WhiteColorCheckBox(
              //   valueStatus: dataStatus.isMicrophoneData,
              //   onChanged: (value) {
              //     setState(() {
              //       _isMicrophoneEnable = value ?? false;
              //       if (_isMicrophoneEnable && _isSampleDataOn) {
              //         _isSampleDataOn = false;
              //         widget.onSampleChange(_isSampleDataOn);
              //       }
              //     });
              //     widget.isMicrophoneEnable(_isMicrophoneEnable);
              //   },
              // ),
              // Text(
              //   "Microphone On",
              //   style: SoftwareTextStyle().kWtMediumTextStyle,
              // )
            ],
          ),
        ],
      );
    });
  }
}

