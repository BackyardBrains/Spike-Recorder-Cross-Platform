// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:spikerbox_architecture/widget/custom_button.dart';

// import '../../../constant/softwaretextstyle.dart';
// import '../../graph_page_widget/sound_wave_view.dart';

// class IsolateScreenTemplate extends StatefulWidget {
//   const IsolateScreenTemplate(
//       {super.key,
//       this.writePort,
//       required this.stream,
//       required this.pauseButton,
//       required this.resumeButton,
//       required this.openPort,
//       required this.readPort});
//   final Stream<Uint8List> stream;
//   final Function? writePort;
//   final Function() pauseButton;
//   final Function() resumeButton;
//   final Function() openPort;
//   final Function() readPort;

//   @override
//   State<IsolateScreenTemplate> createState() => _IsolateScreenTemplateState();
// }

// class _IsolateScreenTemplateState extends State<IsolateScreenTemplate> {
//   @override
//   Widget build(BuildContext context) {
//     return SizedBox(
//       width: MediaQuery.of(context).size.width,
//       height: MediaQuery.of(context).size.height,
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Expanded(
//             flex: 4,
//             child: Column(
//               children: [
//                 // Expanded(
//                 //   flex: 4,
//                 //   child: SoundWaveView(
//                 //     stream: widget.stream,
//                 //   ),
//                 // ),
//                 Expanded(
//                     flex: 1,
//                     child: BottomButtons(
//                       pauseButton: widget.pauseButton,
//                       resumeButton: widget.resumeButton,
//                     ))
//               ],
//             ),
//           ),
//           Expanded(
//             flex: 1,
//             child:  Row(
//                               crossAxisAlignment: CrossAxisAlignment.start,
//                               children: [
                             
              
//                 const SizedBox(width: 16),
//                SizedBox(
//                                      height: 50,
//                                   width: 80,
//                                   child: FittedBox(
//                                     child: CustomButton(
//                                        colors: Colors.blue[500],
//                                       onTap: widget.readPort,
//                                       childWidget: Text("Recieve",style:SoftwareTextStyle().kWtMediumTextStyle,),
//                                     ),
//                                   ),
//                                 ),
//                  const SizedBox(width: 16),
//                SizedBox(
//                                      height: 50,
//                                   width: 80,
//                                   child: FittedBox(
//                                     child: CustomButton(
//                                        colors: Colors.blue[500],
//                                       onTap: (){
//                     if(widget.writePort == null) return;
//                     widget.writePort;},
//                                       childWidget: Text("Write",style:SoftwareTextStyle().kWtMediumTextStyle,),
//                                     ),
//                                   ),
//                                 ),
//                               ],
//                             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
