import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spikerbox_architecture/widget/custom_button.dart';
import 'package:url_launcher/url_launcher.dart';

class DashBoardPannel extends StatefulWidget {
  const DashBoardPannel({super.key});

  @override
  State<DashBoardPannel> createState() => _DashBoardPannelState();
}

class _DashBoardPannelState extends State<DashBoardPannel> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("Backyard Brains")),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(
              height: 250,
              width: 250,
              child: Image.asset("assets/spiker_logo.jpeg"),
            ),
            ListView.builder(
              shrinkWrap: true,
              itemCount: downLoadFileList.length,
              itemBuilder: (context, index) => Column(
                children: [
                  const SizedBox(
                    height: 20,
                  ),
                  CustomButton(
                    onTap: () {
                      openWebPageInNewTab(downLoadFileList[index].url);
                    },
                    childWidget: Text(downLoadFileList[index].fileName),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void openWebPageInNewTab(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(
        Uri.parse(url),
      );
    } else {
      throw 'Could not launch $url';
    }
  }
}

List<DownLoadTheFile> downLoadFileList = [
  DownLoadTheFile(
      fileName: "ProtoType 1.0.0",
      url:
          "https://google.com"),

];

class DownLoadTheFile {
  DownLoadTheFile({
    required this.url,
    required this.fileName,
  });

  String url;
  String fileName;
}
