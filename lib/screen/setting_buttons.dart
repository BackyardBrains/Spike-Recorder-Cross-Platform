import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/functionality/device_functionality/device_status_functionality.dart';
import 'package:spikerbox_architecture/screen/graph_page_widget/sound_wave_view.dart';

import '../models/models.dart';
import '../provider/provider_export.dart';
import '../widget/widget_export.dart';

class SettingButtons extends StatefulWidget {
  const SettingButtons({super.key});

  @override
  State<SettingButtons> createState() => _SettingButtonsState();
}

class _SettingButtonsState extends State<SettingButtons> {
  DeviceStatusFunctionality deviceStatusFunctionality =
      DeviceStatusFunctionality();

  bool isDeviceConnect = true;
  @override
  Widget build(BuildContext context) {
    ConstantProvider constantProvider = Provider.of<ConstantProvider>(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SpikerBoxButton(
                    onTapButton: () async {
                      context
                          .read<SoftwareConfigProvider>()
                          .settingStatus(true);
                    },
                    iconData: Icons.settings),
                const SizedBox(
                  width: 10,
                ),
                // SpikerBoxButton(
                //     onTapButton: () async {}, iconData: Icons.graphic_eq),
                // const SizedBox(
                //   width: 10,
                // ),
                SpikerBoxButton(
                  onTapButton: () {},
                  iconData: Icons.graphic_eq_outlined,
                ),
                const SizedBox(
                  width: 10,
                ),

                Consumer<SerialDataProvider>(
                  builder: (context, connectedDevices, snapshot) {
                    if (connectedDevices.deviceWithComData.isNotEmpty) {
                      List<ComDataWithBoard> listOfBoard =
                          connectedDevices.deviceWithComData;

                      return SizedBox(
                        height: 50,
                        child: ListView.builder(
                            padding: EdgeInsets.zero,
                            scrollDirection: Axis.horizontal,
                            shrinkWrap: true,
                            itemCount: listOfBoard.length,
                            itemBuilder: (context, index) {
                              // int enableDevice = listOfBoard.length - 1;
                              return Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: SpikerBoxButton(
                                    // deviceOn: index == enableDevice,
                                    onTapButton: () async {
                                      DataStatusProvider dataStatus =
                                          context.read<DataStatusProvider>();
                                   
                                      bool dummyDataStatus =
                                          dataStatus.isSampleDataOn;
                                      bool isAudioListen =
                                          dataStatus.isMicrophoneData;

                                      // print(
                                      //     "the enable index is $enableDevice and $index");
                                      // enableDevice = index;
                                      int baudRate = listOfBoard[index]
                                                  .connectDevices
                                                  .uniqueName ==
                                              "HHIBOX"
                                          ? 500000
                                          : 222222;
                                      constantProvider.setBaudRate(baudRate);
                                      constantProvider.setChannelCount(
                                          int.parse(listOfBoard[index]
                                              .connectDevices
                                              .maxNumberOfChannels
                                              .toString()));
                                      constantProvider.setBitData(int.parse(
                                          listOfBoard[index]
                                              .connectDevices
                                              .sampleResolution
                                              .toString()));

                                      await deviceStatusFunctionality
                                          .listenDevice(
                                        dummyDataStatus,
                                        isAudioListen,
                                        listOfBoard[index]
                                            .serialPortData
                                            .portCom,
                                        baudRate,
                                      );
                                    },
                                    iconData: Icons.usb),
                              );
                            }),
                      );
                    } else {
                      return Container();
                    }
                  },
                ),
              ],
            ),
            Row(
              children: [
                SpikerBoxButton(
                  onTapButton: () {},
                  iconData: Icons.fiber_manual_record,
                  iconColor: Colors.red,
                ),
                const SizedBox(
                  width: 10,
                ),
                SpikerBoxButton(onTapButton: () {}, iconData: Icons.menu)
              ],
            )
          ],
        ),
        BottomButtons(
          pauseButton: (bool isPlay) {
            Provider.of<GraphResumePlayProvider>(context, listen: false)
                .setGraphResumePlay(isPlay);
          },
        ),
      ],
    );
  }
}
