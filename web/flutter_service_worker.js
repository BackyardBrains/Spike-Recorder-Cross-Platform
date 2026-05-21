'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "697581f7b784a08dc346d6782bae9ba3",
"version.json": "49c716cf2f4f59a7a107c244ef1d9694",
"low_pass_filter.cpp": "bee16c9a3393c7c7d91939b4074eaec6",
"a.out.wasm": "a8eacac2cd448e2cd5693d50dbb442ca",
"index.html": "87bdb271b23476558f7decee0768eedc",
"/": "87bdb271b23476558f7decee0768eedc",
"audio_processor.js": "3738b2bed03753ff6d37252400554407",
"workerSimulation.js": "fa8cbe806c91bfcbc4b803c6eecfe15c",
"native_add.js": "08139589c1631970b7bae85d0e5362ac",
"ProcessThread.js": "d979c86917e428621517d19bd9d57e90",
"main.dart.js": "752a9929c1d7c3b3cd35fb29d4e39d2f",
"wavfile.js": "d89da191858c1509b8cb575e2cbe52a0",
"flutter.js": "f393d3c16b631f36852323de8e583132",
"index.js": "84994372a17b4619e210fe31e80c86e6",
"microphone_util.js": "ec07f02ad2001dc84ae9a452aa9fdcd0",
"cprocessing.wasm": "42c15d12b5d10e59c3976d4460bdd726",
"native_add.cpp": "c0d6c5bfb2bdbda3b7faa66c5f73cee4",
"nwbfile_plugin.wasm": "c689376ba54d15f3188de120a02ad051",
"nwbfile_plugin.js": "c2344f9b2c4956f12de59041ad026d56",
"cprocessing.js": "3a98636879dac60d4a70d32b4bd7d61f",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"main_entry_file.cpp": "3091f4291518407c12e8ed969beaa59e",
"a.out.worker.js": "077aadae991a00b9159782ea46653bcf",
"filter_base.h": "141c20bdbd59f8dcc86f5adbbfeaa644",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"manifest.json": "b5c81ed5e8f46bf2e220b9a311cc3d53",
"worker6788.dart": "e34fe1274e220ca72d13269b2bb406de",
"main.dart.js_1.part.js": "f568c9215993bc0375c23287ebb7b9e2",
"filter_base.cpp": "f7d594facf762bf4c0c9bbf7982ecc44",
".vscode/extensions.json": "83a9e2ad4d0f05c4b8e3918c126c9451",
"main.dart.js_3.part.js": "e66f24db5e2acfadd0241881d36ea9db",
"assets/AssetManifest.json": "d50c56757fadb786d6c5fcc725d912d3",
"assets/NOTICES": "1f4285b02bb414f8451a67ac3cfb11a3",
"assets/FontManifest.json": "be13a5dd509a27dc6b1e759f65ae7aea",
"assets/AssetManifest.bin.json": "91afca71bdf66c4135a5eb98e1c45171",
"assets/packages/window_manager/images/ic_chrome_unmaximize.png": "4a90c1909cb74e8f0d35794e2f61d8bf",
"assets/packages/window_manager/images/ic_chrome_minimize.png": "4282cd84cb36edf2efb950ad9269ca62",
"assets/packages/window_manager/images/ic_chrome_maximize.png": "af7499d7657c8b69d23b85156b60298c",
"assets/packages/window_manager/images/ic_chrome_close.png": "75f4b8ab3608a05461a31fc18d6b47c2",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "b93248a553f9e8bc17f1065929d5934b",
"assets/packages/flutter_soloud/web/worker.dart.js": "2fddc14058b5cc9ad8ba3a15749f9aef",
"assets/packages/flutter_soloud/web/init_module.dart.js": "ea0b343660fd4dace81cfdc2910d14e6",
"assets/packages/flutter_soloud/web/libflutter_soloud_plugin.js": "328542a0581477d30370a3f2929fbb7e",
"assets/packages/flutter_soloud/web/libflutter_soloud_plugin.wasm": "96e558342d9f27f5d10121484c51501e",
"assets/packages/panara_dialogs/assets/info.png": "e4bb5858c90ab48c72f11ba44bb26b5b",
"assets/packages/panara_dialogs/assets/confirm.png": "acf806139cb7c12e09fc5ca1185b8a2f",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "6d247986689d283b7e45ccdf7214c2ff",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin": "8a0425493de68592b743cab080f82c6b",
"assets/fonts/MaterialIcons-Regular.otf": "e7069dfd19b331be16bed984668fe080",
"assets/assets/recordwithsoftware.txt": "619144803f8dd7b6740fbe25875970f5",
"assets/assets/default_config.json": "0eddeb0590c2d74603c21f74a61528ac",
"assets/assets/textSearch.txt": "d41d8cd98f00b204e9800998ecf8427e",
"assets/assets/spiker_logo.jpeg": "73f333fed257f2f5180239ea05fc274c",
"assets/assets/icons/button_custom.svg": "94a20ab11352a4794f1f544e197126a7",
"assets/assets/icons/button_preferences.svg": "d7548d4f7c953e8d9cf2ddacb2b7402a",
"assets/assets/icons/config_neuron_off.svg": "dbe798b744d7fc428c178e915ab288e6",
"assets/assets/icons/config_emg_off.svg": "6d7645c8d0bba5d4a11e50fc2eebe53a",
"assets/assets/icons/config_board.svg": "261e83acfc88c95cafb396a3cf10399e",
"assets/assets/icons/config_ecg_off.svg": "8663a9db4df4c0fbf5b183a34004e3e9",
"assets/assets/icons/config_eeg_off.svg": "931596a6548d2c1bddb570f2d51d2710",
"assets/assets/icons/config_plant_off.svg": "fa9147dd6794b73fca19a16f66206780",
"assets/assets/libopus.js": "5ddd2b3f84a5a2e6c7325cec46e53f53",
"assets/assets/optimized/config_emg_off.svg.vec": "1101fc5c933a044c4475cb5e60617868",
"assets/assets/fonts/byb_sr_symbols.ttf": "dda7f9a5fc12d559fcfe74279766f072",
"high_pass_filter.cpp": "44b6db67c1c6246b56eb7cd829dac134",
"main.dart.js_2.part.js": "60fcb59a122e30a8efd7ba7bb275d3e7",
"a.out.js": "90e8557b3a55917452715845541c7493",
"canvaskit/skwasm.js": "694fda5704053957c2594de355805228",
"canvaskit/skwasm.js.symbols": "262f4827a1317abb59d71d6c587a93e2",
"canvaskit/canvaskit.js.symbols": "48c83a2ce573d9692e8d970e288d75f7",
"canvaskit/skwasm.wasm": "9f0c0c02b82a910d12ce0543ec130e60",
"canvaskit/chromium/canvaskit.js.symbols": "a012ed99ccba193cf96bb2643003f6fc",
"canvaskit/chromium/canvaskit.js": "671c6b4f8fcc199dcc551c7bb125f239",
"canvaskit/chromium/canvaskit.wasm": "b1ac05b29c127d86df4bcfbf50dd902a",
"canvaskit/canvaskit.js": "66177750aff65a66cb07bb44b8c6422b",
"canvaskit/canvaskit.wasm": "1f237a213d7370cf95f443d896176460",
"canvaskit/skwasm.worker.js": "89990e8c92bcb123999aa81f7e203b1c"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
