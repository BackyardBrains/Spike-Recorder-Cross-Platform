import 'dart:async';
import 'dart:html';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:serial/serial.dart';
import 'package:spikerbox_architecture/models/constant.dart';
import 'package:spikerbox_architecture/screen/web_platform/isolates_screen/squadron/identify_service.dart';
import 'package:spikerbox_architecture/screen/web_platform/isolates_screen/squadron/sample_service.dart';
import 'package:spikerbox_architecture/screen/web_platform/isolates_screen/squadron/sample_worker_vm.dart'
    as sample_isolate;
import 'package:squadron/squadron.dart';
import 'package:spikerbox_architecture/screen/web_platform/isolates_screen/squadron/sampleworker_pool.dart';



class SquadronPages extends StatefulWidget {
  const SquadronPages({Key? key}) : super(key: key);

  @override
  State<SquadronPages> createState() => _SquadronPagesState();
}

class _SquadronPagesState extends State<SquadronPages> {
  Squadron? squadron;
  SerialPort? _port;
  final _received = <String>[];
  SerialPortInfo? portInfo;
  Future<void> _openPort() async {
    final port = await window.navigator.serial.requestPort();
    await port.open(baudRate: 222222);
    portInfo = port.getInfo();

    _port = port;
    setState(() {});
  }

  Future<void> _writeToPort() async {
    if (_port == null) {
      return;
    }

    final writer = _port!.writable.writer;

    await writer.ready;
    await writer.write(Uint8List.fromList('Hello World.'.codeUnits));

    await writer.ready;
    await writer.close();
  }

  Future<void> _readFromPort() async {
    if (_port == null) {
      return;
    }

    final reader = _port!.readable.reader;
    while (true) {
      final ReadableStreamDefaultReadResult result = await reader.read();

      // 3. squadron package in web
      // final worker = Squadron(
      //   entryPoint: 'my_worker',
      //   args: const ['Hello', 'World'],
      // );

      // // Start the worker.
      // worker.start();

      // // Wait for the worker to finish.
      // await worker.join();

      // // Get the worker's output.
      // final output = worker.output;

      // // Print the output to the console.
      // print(output);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((timeStamp) async {
      // Squadron.setId('spiker');
      // Squadron.setLogger(ConsoleSquadronLogger());
      // Squadron.logLevel = SquadronLogLevel.all;
      await squadronIsolateCheck();
    });
  }

  Offset renderCenter = const Offset(-0.75, 0);
  double renderWidth = 3.5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Serial'),
      ),
      body: Column(
        children: [
          portInfo != null
              ? ListTile(
                  title: Text(
                    portInfo!.usbProductId.toString(),
                  ),
                  subtitle: Text(portInfo!.usbVendorId.toString()),
                )
              : const Text("No device is detected"),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: _received.map((e) => Text(e)).toList(),
            ),
          ),
          ElevatedButton(
            child: const Text('Open Port'),
            onPressed: () {
              _openPort();
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            child: const Text('Send'),
            onPressed: () {
              _writeToPort();
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            child: const Text('Receive'),
            onPressed: () async {
              await _readFromPort();
            },
          ),
        ],
      ),
    );
  }

  Future squadronIsolateCheck() async {
    final sw = Stopwatch()..start();

    Squadron.setId('MAIN');
    Squadron.debugMode = false;
    Squadron.logLevel = SquadronLogLevel.info;
    Squadron.setLogger(ConsoleSquadronLogger());

    void log([String? message]) {
      message ??= '';
      Squadron.info(message.isEmpty ? ' ' : '[${sw.elapsed}] $message');
    }

    final loops = 5;
    final max = 50;

    log();
    log('loops = $loops');
    log('max = $max');
    log();

    final identityService = IdentityServiceImpl();
    final identityServer = LocalWorker<IdentityService>.create(identityService);
    final identityClient = IdentityClient(identityServer.channel!.share());
    final sampleService = SampleServiceImpl(identityClient);

    SampleWorkerPool? pool;

    try {
      ///////////// SYNC /////////////
      log('///////////// SYNC /////////////');

      final syncSw = Stopwatch()..start();
      for (var loop = 0; loop < loops; loop++) {
        final syncFutures = <Future>[];
        for (var n = 0; n < max; n++) {
          syncFutures
            ..add(Future(() => sampleService.cpu(milliseconds: n)))
            ..add(sampleService.io(milliseconds: n));
        }
        await Future.wait(syncFutures);
      }
      syncSw.stop();
      final syncElapsed = syncSw.elapsedMicroseconds;

      log('sync version completed in ${Duration(microseconds: syncElapsed)}');
      log();

      ///////////// POOL /////////////
      log('///////////// POOL /////////////');

      // create the pool
      final concurrencySettings =
          ConcurrencySettings(minWorkers: 2, maxWorkers: 4, maxParallel: 2);

      pool = SampleWorkerPool(
          sample_isolate.start, identityServer, concurrencySettings);
      await pool.start();
      log('pool started');

      // create the pool monitor
      final maxIdle = Duration(milliseconds: 1000);
      final monitor = Timer.periodic(Duration(milliseconds: 250), (timer) {
        pool?.stop((w) => w.idleTime > maxIdle);
      });

      log('pool monitor started');

      final tasks = <Future>[];

      // force maximum load on pool
      for (var i = 0; i < pool.maxConcurrency; i++) {
        tasks.add(pool.cpu(milliseconds: 5));
      }

      await Future.wait(tasks);

      // 4 workers should have been started
      assert(pool.size == 2);
      // sit idle to that the pool monitor stops 2 of them
      await Future.delayed(maxIdle * 2);
      assert(pool.size == 2);
      log('pool monitor OK');

      final asyncSw = Stopwatch()..start();
      for (var loop = 0; loop < loops; loop++) {
        final asyncFutures = <Future>[];
        for (var n = 0; n < max; n++) {
          asyncFutures
            ..add(pool.cpu(milliseconds: n))
            ..add(pool.io(milliseconds: n));
        }
        await Future.wait(asyncFutures);
      }
      asyncSw.stop();
      final asyncElapsed = asyncSw.elapsedMicroseconds;

      log('async version completed in ${Duration(microseconds: asyncElapsed)}');
      log();

      ///////////// LOCAL WORKER /////////////
      log('///////////// LOCAL WORKER /////////////');

      log('IdentityClient is ${await identityClient.whoAreYou()}.');
      log(await sampleService.whoAreYouTalkingTo());

      tasks.clear();
      for (var i = 0; i < pool.maxConcurrency + 1; i++) {
        tasks.add(pool.whoAreYouTalkingTo().then(log));
      }
      await Future.wait(tasks);

      // stop the identity local worker
      identityServer.stop();

      // shutdown pool
      log('waiting for monitor to stop workers...');
      final sw = Stopwatch()..start();
      while (true) {
        final size = pool.size;
        log('  * pool.size = $size');
        if (size <= pool.concurrencySettings.minWorkers) break;
        await Future.delayed(maxIdle ~/ 2);
        if (sw.elapsedMicroseconds > maxIdle.inMicroseconds * 2) {
          log('Houston, we have a problem...');
        }
      }

      log('worker stats:');
      for (var stat in pool.fullStats) {
        log('  * ${stat.id}: status=${stat.status}, workload=${stat.workload}, maxWorkload=${stat.maxWorkload}, totalWorkload=${stat.totalWorkload}, totalErrors=${stat.totalErrors}');
      }

      monitor.cancel();

      log('pool stats:');
      log('  * size=${pool.size}, workload=${pool.workload}, maxLoad=${pool.maxWorkload}, totalWorkload=${pool.totalWorkload}, totalErrors=${pool.totalErrors}');

      log();
    } on WorkerException catch (e) {
      log(e.message);
      log(e.stackTrace?.toString());
    } finally {
      pool?.stop();
    }

    log('Done.');
    log();
  }
}

class SampleService implements WorkerService {
  Future io({required int milliseconds}) =>
      Future.delayed(Duration(milliseconds: milliseconds));

  void cpu({required int milliseconds}) {
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < milliseconds) {/* cpu */}
  }

  static const ioCommand = 1;
  static const cpuCommand = 2;

  @override
  Map<int, CommandHandler> get operations => {
        ioCommand: (WorkerRequest r) => io(milliseconds: r.args[0]),
        cpuCommand: (WorkerRequest r) => cpu(milliseconds: r.args[0]),
      };
}
