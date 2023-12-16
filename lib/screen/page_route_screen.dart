import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/screen/admin_dashboard_screen/admin_screen.dart';
import 'package:spikerbox_architecture/screen/graph_template.dart';

import '../provider/devices_provider.dart';
import '../widget/custom_button.dart';

class DashBoardPageRoute extends StatefulWidget {
  const DashBoardPageRoute({super.key});

  @override
  State<DashBoardPageRoute> createState() => _DashBoardPageRouteState();
}

class _DashBoardPageRouteState extends State<DashBoardPageRoute> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Backyard Brains"),
      ),
      body: Center(
        child: Column(
          children: [
            SizedBox(
              height: 250,
              width: 250,
              child: Image.asset("assets/spiker_logo.jpeg"),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: CustomButton(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const DashBoardPannel()),
                  );
                },
                childWidget: const Text("Download Prototypes"),
              ),
            ),
            Consumer<ConstantProvider>(builder: (context, data, child) {
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: CustomButton(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) {
                          return GraphTemplate(
                            constantProvider: data,
                          );
                        },
                      ),
                    );
                  },
                  childWidget: const Text("Web application"),
                ),
              );
            })
          ],
        ),
      ),
    );
  }
}
