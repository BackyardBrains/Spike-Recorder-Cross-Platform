
import 'package:flutter/material.dart';
import 'package:native_add/model/filter_select_enum.dart';
import 'package:native_add/model/filterbase_setting.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/constant/colors_constant.dart';
import 'package:spikerbox_architecture/constant/softwaretextstyle.dart';
import 'package:spikerbox_architecture/models/constant.dart';
import 'package:spikerbox_architecture/provider/data_type_status.dart';
import 'package:spikerbox_architecture/provider/sample_rate_provider.dart';

class NotchPassFilterWidget extends StatelessWidget {
  const NotchPassFilterWidget({
    super.key,
    required this.onTapNotchFrequency,
  });

  final Function(FilterSetup) onTapNotchFrequency;

  FilterSetup _buildSettings(int cutOffFrequency, int sampleRate, bool isOn) {
    return FilterSetup(
      filterConfiguration: FilterConfiguration(
        cutOffFrequency: cutOffFrequency,
        sampleRate: sampleRate,
      ),
      filterType: FilterType.notchFilter,
      channelCount: channelCountBuffer,
      isFilterOn: isOn,
    );
  }

  void _apply50Hz(
    BuildContext context,
    bool checked,
    int sampleRate,
  ) {
    final dataStatus = context.read<DataStatusProvider>();
    if (checked) {
      dataStatus.set60HertzStatus(false);
    }
    dataStatus.set50HertzStatus(checked);
    onTapNotchFrequency(_buildSettings(50, sampleRate, checked));
  }

  void _apply60Hz(
    BuildContext context,
    bool checked,
    int sampleRate,
  ) {
    final dataStatus = context.read<DataStatusProvider>();
    if (checked) {
      dataStatus.set50HertzStatus(false);
    }
    dataStatus.set60HertzStatus(checked);
    onTapNotchFrequency(_buildSettings(60, sampleRate, checked));
  }

  @override
  Widget build(BuildContext context) {
    final dataStatus = context.watch<DataStatusProvider>();
    final sampleRate = context.watch<SampleRateProvider>().sampleRate;
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
          child: const Icon(
            IconData(0xe90b, fontFamily: "IcomoonIcons"),
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          MediaQuery.of(context).orientation == Orientation.portrait ? "Notch filter : " : "Attenuate frequency (Notch filter) : ",
          style: SoftwareTextStyle().kWtMediumTextStyle,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
            child: Row(
              children: [
                Text(
                  "50 Hz",
                  style: SoftwareTextStyle().kWtMediumTextStyle,
                ),
                WhiteColorCheckBox(
                  value: dataStatus.is50Hertz,
                  onChanged: (checked) =>
                      _apply50Hz(context, checked, sampleRate),
                ),
                const SizedBox(width: 16),
                Text(
                  "60 Hz",
                  style: SoftwareTextStyle().kWtMediumTextStyle,
                ),
                WhiteColorCheckBox(
                  value: dataStatus.is60Hertz,
                  onChanged: (checked) =>
                      _apply60Hz(context, checked, sampleRate),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


class WhiteColorCheckBox extends StatelessWidget {
  const WhiteColorCheckBox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  static const double _size = 20;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: value ? SoftwareColors.kGraphColor : Colors.transparent,
            border: Border.all(color: Colors.white, width: 1.5),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: value
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
