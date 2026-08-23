import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: home + "/.config/omarchy/wallpaper-rotate"
  readonly property string configPath: configDir + "/config.json"
  readonly property string themeNamePath: home + "/.local/state/omarchy/current/theme.name"
  readonly property string currentBgLink: home + "/.local/state/omarchy/current/background"
  readonly property string catalogScriptPath: decodeURIComponent(
    String(Qt.resolvedUrl("Catalog.sh")).replace(/^file:\/\//, ""))
  readonly property string boundedReadScriptPath: decodeURIComponent(
    String(Qt.resolvedUrl("BoundedRead.pl")).replace(/^file:\/\//, ""))
  readonly property int configMaxBytes: 262144
  readonly property int themeNameMaxBytes: 4096
  readonly property int directoryMaxChars: 4096
  readonly property string repoUrl: "https://github.com/Somnius/Omarchy-Wallpaper-Rotate"

  // Config (persisted in config.json). `enabled` and `intervalMinutes` are
  // literal so the shipped defaults always apply for fresh installs and
  // aren't lost to a stale cached state or a write racing the file load.
  property bool loaded: false
  property bool enabled: true
  property int intervalMinutes: 5
  property string mode: "random"          // sequential | random | shuffle
  property string directory: "~/Pictures/wallpapers"

  // Rotation state (persisted so restarts don't repeat recent picks).
  property double lastChangeEpoch: 0
  property int position: 0                // sequential cursor
  property var cycle: []                  // shuffle playlist of paths
  property int cycleIndex: 0
  property string cycleDir: ""            // directory the cycle was built for

  // Live state.
  property var catalogPaths: []
  property var wallpaperList: []          // [{path, thumb, name}]
  property string currentWallpaper: ""
  property double nowEpoch: 0

  // Action state.
  property bool busy: false
  property string pendingWallpaper: ""
  property var pendingPatch: null
  property string pendingApplyDirectory: ""
  property string lastError: ""
  property string lastAction: ""

  property bool configReadPending: false
  property bool themeReadPending: false
  property bool themeInitialized: false
  property string catalogReadDirectory: ""

  function currentConfig() {
    return {
      enabled: root.enabled,
      intervalMinutes: root.intervalMinutes,
      mode: root.mode,
      directory: root.directory,
      lastChangeEpoch: root.lastChangeEpoch,
      position: root.position,
      cycle: root.cycle,
      cycleIndex: root.cycleIndex,
      cycleDir: root.cycleDir
    }
  }

  function normalize(config) {
    var c = config || {}
    var out = {}
    out.enabled = c.enabled !== false
    var minutes = Math.round(Number(c.intervalMinutes))
    if (!isFinite(minutes)) minutes = 5
    out.intervalMinutes = Math.max(1, Math.min(1440, minutes))
    out.mode = ["sequential", "random", "shuffle"].indexOf(c.mode) >= 0 ? c.mode : "random"
    out.directory = root.validDirectory(c.directory)
      ? c.directory.trim() : "~/Pictures/wallpapers"
    out.lastChangeEpoch = (isFinite(c.lastChangeEpoch)
        && c.lastChangeEpoch > 0 && c.lastChangeEpoch < 1e15)
      ? c.lastChangeEpoch : 0
    out.position = Math.max(0, Math.round(Number(c.position)) || 0)
    out.cycle = Array.isArray(c.cycle) ? c.cycle.filter(function (p) { return typeof p === "string" }).slice(0, 50) : []
    out.cycleIndex = Math.max(0, Math.round(Number(c.cycleIndex)) || 0)
    out.cycleDir = typeof c.cycleDir === "string" ? c.cycleDir : ""
    return out
  }

  function validConfigShape(config) {
    if (config === null || typeof config !== "object" || Array.isArray(config)) return false
    if (config.enabled !== undefined && typeof config.enabled !== "boolean") return false
    if (config.intervalMinutes !== undefined
        && (typeof config.intervalMinutes !== "number" || !isFinite(config.intervalMinutes))) return false
    if (config.mode !== undefined
        && ["sequential", "random", "shuffle"].indexOf(config.mode) < 0) return false
    if (config.directory !== undefined && !root.validDirectory(config.directory)) return false
    if (config.lastChangeEpoch !== undefined
        && (typeof config.lastChangeEpoch !== "number" || !isFinite(config.lastChangeEpoch))) return false
    if (config.position !== undefined
        && (typeof config.position !== "number" || !isFinite(config.position))) return false
    if (config.cycleIndex !== undefined
        && (typeof config.cycleIndex !== "number" || !isFinite(config.cycleIndex))) return false
    if (config.cycleDir !== undefined && typeof config.cycleDir !== "string") return false
    if (config.cycle !== undefined) {
      if (!Array.isArray(config.cycle)) return false
      for (var i = 0; i < config.cycle.length; i++) {
        if (typeof config.cycle[i] !== "string") return false
      }
    }
    return true
  }

  function validDirectory(value) {
    if (typeof value !== "string") return false
    if (value.length > root.directoryMaxChars) return false
    if (/[\u0000-\u001f\u007f]/.test(value)) return false
    var path = value.trim()
    if (path === "") return false
    return path === "~" || path.indexOf("~/") === 0 || path.indexOf("/") === 0
  }

  function expandPath(path) {
    var p = String(path || "")
    if (p === "~") return home
    if (p.indexOf("~/") === 0) return home + p.substring(1)
    return p
  }

  function applyConfig(text) {
    var parsed
    try { parsed = JSON.parse(String(text)) }
    catch (error) {
      root.lastError = "Invalid config.json: " + error
      return false
    }
    if (!root.validConfigShape(parsed)) {
      root.lastError = "Invalid config.json: expected a configuration object"
      return false
    }
    var firstLoad = !root.loaded
    var previousDirectory = root.directory
    var config = normalize(parsed)
    // A brand-new config has lastChangeEpoch 0; start the clock now so the
    // first scheduled change waits one full interval instead of firing at once.
    if (config.enabled && config.lastChangeEpoch <= 0) config.lastChangeEpoch = Date.now()
    root.enabled = config.enabled
    root.intervalMinutes = config.intervalMinutes
    root.mode = config.mode
    root.directory = config.directory
    root.lastChangeEpoch = config.lastChangeEpoch
    root.position = config.position
    root.cycle = config.cycle
    root.cycleIndex = config.cycleIndex
    root.cycleDir = config.cycleDir
    root.loaded = true
    root.nowEpoch = Date.now()
    if (firstLoad || previousDirectory !== root.directory) {
      root.catalogPaths = []
      root.wallpaperList = []
      Qt.callLater(function () { root.refreshCatalog(false) })
    }
    Qt.callLater(root.reconcile)
    return true
  }

  function clearConfigReadError() {
    if (root.lastError.indexOf("Invalid config.json:") === 0
        || root.lastError.indexOf("Could not read config.json:") === 0)
      root.lastError = ""
  }

  function clearThemeReadError() {
    if (root.lastError === "Invalid theme.name"
        || root.lastError.indexOf("Could not read theme.name:") === 0)
      root.lastError = ""
  }

  function saveConfig(patch) {
    var config = root.currentConfig()
    for (var key in patch) config[key] = patch[key]
    config = normalize(config)
    // FileView retains its last written value when reads are disabled. Reset
    // that cache so an externally replaced file can never suppress this write.
    configFile.path = ""
    configFile.path = root.configPath
    configFile.setText(JSON.stringify(config, null, 2) + "\n")
    if (root.applyConfig(JSON.stringify(config))) root.clearConfigReadError()
  }

  function requestConfigRead() {
    if (configReadProc.running) {
      root.configReadPending = true
      return
    }
    root.configReadPending = false
    configReadProc.running = true
  }

  function requestThemeRead() {
    if (themeReadProc.running) {
      root.themeReadPending = true
      return
    }
    root.themeReadPending = false
    themeReadProc.running = true
  }

  function readFailure(stderrText, fallback) {
    var detail = String(stderrText || "").trim()
    return detail || fallback
  }

  function onConfigReadExited(exitCode) {
    var stale = root.configReadPending
    root.configReadPending = false
    if (stale) {
      Qt.callLater(root.requestConfigRead)
      return
    }

    var hadConfig = root.loaded
    if (exitCode === 0) {
      if (root.applyConfig(configReadOutput.text)) {
        root.clearConfigReadError()
      } else if (!root.loaded) {
        var parseError = root.lastError
        root.applyConfig("{}")
        root.lastError = parseError
      }
    } else {
      if (!root.loaded) root.applyConfig("{}")
      if (exitCode !== 2 || hadConfig) {
        root.lastError = "Could not read config.json: "
          + readFailure(configReadError.text, "bounded read failed")
      }
    }

  }

  function applyThemeName(text) {
    var raw = String(text || "")
    if (!/^[^\r\n\u0085\u2028\u2029]+(?:\r?\n)?$/.test(raw)) {
      root.lastError = "Invalid theme.name"
      return false
    }
    var theme = raw.replace(/\r?\n$/, "").trim()
    if (theme === "" || /[\u0000-\u001f\u007f]/.test(theme)) {
      root.lastError = "Invalid theme.name"
      return false
    }
    if (!root.themeInitialized) {
      root.currentTheme = theme
      root.themeInitialized = true
    } else {
      root.onThemeChanged(theme)
    }
    return true
  }

  function onThemeReadExited(exitCode) {
    var stale = root.themeReadPending
    root.themeReadPending = false
    if (stale) {
      Qt.callLater(root.requestThemeRead)
      return
    }

    if (exitCode === 0) {
      if (root.applyThemeName(themeReadOutput.text)) root.clearThemeReadError()
    } else if (exitCode !== 2 || root.currentTheme !== "") {
      root.lastError = "Could not read theme.name: "
        + readFailure(themeReadError.text, "bounded read failed")
    }

  }

  function setEnabled(value) {
    root.saveConfig({ enabled: value === true })
    if (value === true) Qt.callLater(root.applyNext)
    else root.lastAction = "Automatic rotation disabled"
  }

  function updateSchedule(patch) {
    root.saveConfig(patch)
    root.lastAction = "Schedule saved"
  }

  function setDirectory(value) {
    if (!root.validDirectory(value)) {
      root.lastError = "Folder must be ~, ~/…, or an absolute path (max "
        + root.directoryMaxChars + " characters)"
      return false
    }
    var path = value.trim()
    if (path === root.directory) {
      root.lastError = ""
      root.lastAction = "Already using " + path
      return true
    }
    root.lastError = ""
    root.saveConfig({
      directory: path,
      lastChangeEpoch: Date.now(),
      position: 0,
      cycle: [],
      cycleIndex: 0,
      cycleDir: ""
    })
    root.lastAction = "Wallpaper folder updated"
    return true
  }

  function updateCurrent() {
    if (!currentProc.running) currentProc.running = true
  }

  // Cheap listing by default; thumbnail generation is deferred until the
  // panel actually opens, so an idle plugin spends ~no resources.
  function refreshCatalog(ensureThumbs) {
    if (ensureThumbs === true) {
      if (!cacheProc.running) cacheProc.running = true
      return
    }
    if (!catalogProc.running) {
      root.catalogReadDirectory = root.directory
      catalogProc.command = ["bash", root.catalogScriptPath,
        expandPath(root.catalogReadDirectory)]
      catalogProc.running = true
    }
  }

  function wallpaperName(path) {
    var base = String(path || "").split("/").pop() || ""
    base = base.replace(/\.[^.]+$/, "")
    base = base.replace(/^\d+-/, "")
    base = base.replace(/[-_]+/g, " ").trim()
    return base.replace(/\b\w/g, function (ch) { return ch.toUpperCase() })
  }

  function nextInMinutes() {
    if (!root.enabled) return -1
    var ms = root.intervalMinutes * 60000 - (root.nowEpoch - root.lastChangeEpoch)
    return Math.max(0, Math.ceil(ms / 60000))
  }

  function nextText() {
    if (!root.enabled) return "Automatic rotation is off"
    if (root.catalogPaths.length === 0) return "No wallpapers found"
    var minutes = root.nextInMinutes()
    var prefix = minutes > 0 ? minutes + " min" : "now"
    return "Next in " + prefix + " · " + wallpaperName(root.currentWallpaper)
  }

  function statusText() {
    return root.catalogPaths.length + " wallpaper"
      + (root.catalogPaths.length === 1 ? "" : "s") + " · "
      + expandPath(root.directory)
  }

  function pickNext() {
    var paths = root.catalogPaths
    var n = paths.length
    if (n === 0) return { changed: false }
    var currentIndex = paths.indexOf(root.currentWallpaper)

    if (root.mode === "shuffle") {
      // Play every wallpaper once before repeating; rebuild when the pool or
      // scan directory changed underneath us.
      if (root.cycleDir !== root.directory || root.cycle.length === 0
          || root.cycleIndex >= root.cycle.length) {
        var pool = paths.slice()
        for (var i = pool.length - 1; i > 0; i--) {
          var j = Math.floor(Math.random() * (i + 1))
          var tmp = pool[i]; pool[i] = pool[j]; pool[j] = tmp
        }
        root.cycle = pool
        root.cycleIndex = 0
        root.cycleDir = root.directory
      }
      for (var step = 0; step < root.cycle.length; step++) {
        var candidate = root.cycle[root.cycleIndex]
        root.cycleIndex += 1
        if (candidate !== root.currentWallpaper || n === 1)
          return { changed: true, path: candidate,
                   patch: { cycle: root.cycle, cycleIndex: root.cycleIndex, cycleDir: root.cycleDir } }
      }
      return { changed: false, patch: { cycle: root.cycle, cycleIndex: root.cycleIndex } }
    }

    if (root.mode === "sequential") {
      var pos = root.position % n
      var picked = paths[pos]
      root.position = pos + 1
      if (picked === root.currentWallpaper && n > 1) {
        pos = root.position % n
        picked = paths[pos]
        root.position = pos + 1
      }
      return { changed: true, path: picked, patch: { position: root.position } }
    }

    // random: any wallpaper except the one currently showing.
    if (n === 1) return { changed: false }
    var pool2 = paths.slice()
    if (currentIndex >= 0) pool2.splice(currentIndex, 1)
    var pick = pool2[Math.floor(Math.random() * pool2.length)]
    return { changed: true, path: pick, patch: {} }
  }

  function applyNext() {
    if (root.busy) return
    root.nowEpoch = Date.now()
    if (!root.enabled) { root.lastAction = "Automatic rotation disabled"; return }
    if (root.catalogPaths.length === 0) {
      // Catalog not ready yet; refresh and retry once it lands.
      pendingApply = true
      root.refreshCatalog(false)
      return
    }
    var result = pickNext()
    if (result.changed && result.path) {
      root.switchTo(result.path, result.patch || {})
    } else {
      root.saveConfig(result.patch || {})
      root.lastAction = root.catalogPaths.length > 0
        ? "Already showing the only wallpaper" : "No wallpapers found"
    }
  }

  property bool pendingApply: false

  function switchTo(path, patch) {
    var target = String(path || "").trim()
    if (!target) { root.lastError = "No wallpaper selected."; return }
    root.pendingWallpaper = target
    root.pendingPatch = patch || {}
    root.pendingApplyDirectory = root.directory
    root.lastError = ""
    setProc.command = ["omarchy-theme-bg-set", target]
    root.busy = true
    setProc.running = true
  }

  function onSetExited(exitCode) {
    root.busy = false
    var applied = root.pendingWallpaper
    var patch = root.pendingPatch || {}
    var applyDirectory = root.pendingApplyDirectory
    root.pendingWallpaper = ""
    root.pendingPatch = null
    root.pendingApplyDirectory = ""
    if (exitCode === 0) {
      root.currentWallpaper = applied
      var statePatch = applyDirectory === root.directory ? patch : {}
      root.saveConfig(Object.assign({ lastChangeEpoch: Date.now() }, statePatch))
      if (!currentProc.running) currentProc.running = true
      root.lastAction = "Wallpaper set to " + wallpaperName(applied)
      root.lastError = ""
    } else {
      root.lastError = String(setError.text || "Wallpaper change failed").trim()
    }
  }

  function reconcile() {
    if (!root.loaded || root.busy) return
    root.nowEpoch = Date.now()
    if (!root.enabled) return
    if (root.nowEpoch - root.lastChangeEpoch >= root.intervalMinutes * 60000) {
      if (root.catalogPaths.length === 0) root.refreshCatalog(false)
      else root.applyNext()
    }
  }

  function onThemeChanged(slug) {
    var theme = String(slug || "").trim()
    if (theme === root.currentTheme) return
    root.currentTheme = theme
    if (!root.loaded) return
    // New theme resets rotation state; let the user see the theme's own
    // choice before the next scheduled switch.
    root.saveConfig({ lastChangeEpoch: Date.now(), position: 0, cycle: [], cycleIndex: 0 })
    root.lastAction = "Theme changed — rotation restarted"
    root.updateCurrent()
  }

  property string currentTheme: ""

  FileView {
    id: configFile
    path: ""
    preload: false
    blockAllReads: true
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onFileChanged: root.requestConfigRead()
  }

  FileView {
    id: themeNameFile
    path: ""
    preload: false
    blockAllReads: true
    watchChanges: true
    printErrors: false
    onFileChanged: root.requestThemeRead()
  }

  Process {
    id: configDirProcess
    command: ["mkdir", "-p", root.configDir]
    onExited: {
      configFile.path = ""
      configFile.path = root.configPath
      root.requestConfigRead()
    }
  }

  Process {
    id: configReadProc
    command: ["/usr/bin/perl", root.boundedReadScriptPath,
      root.configPath, String(root.configMaxBytes)]
    stdout: StdioCollector {
      id: configReadOutput
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: configReadError
      waitForEnd: true
    }
    onExited: function(exitCode) { root.onConfigReadExited(exitCode) }
  }

  Process {
    id: themeReadProc
    command: ["/usr/bin/perl", root.boundedReadScriptPath,
      root.themeNamePath, String(root.themeNameMaxBytes)]
    stdout: StdioCollector {
      id: themeReadOutput
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: themeReadError
      waitForEnd: true
    }
    onExited: function(exitCode) { root.onThemeReadExited(exitCode) }
  }

  Process {
    id: catalogProc
    stdout: StdioCollector {
      id: catalogOutput
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: catalogStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (root.catalogReadDirectory !== root.directory) {
        Qt.callLater(function () { root.refreshCatalog(false) })
        return
      }
      if (exitCode !== 0) {
        root.lastError = String(catalogStderr.text || "Could not list wallpapers").trim()
        return
      }
      var paths = []
      var list = []
      var lines = String(catalogOutput.text || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var row = lines[i].split("\t")
        if (!row[0]) continue
        paths.push(row[0])
        list.push({ path: row[0], thumb: row[1] || row[0], name: wallpaperName(row[0]) })
      }
      root.catalogPaths = paths
      root.wallpaperList = list
      if (root.pendingApply) {
        root.pendingApply = false
        Qt.callLater(root.applyNext)
      }
      Qt.callLater(root.reconcile)
    }
  }

  Process {
    id: cacheProc
    command: ["omarchy-theme-bg-cache"]
    onExited: root.refreshCatalog(false)
  }

  Process {
    id: currentProc
    command: ["readlink", "-f", root.currentBgLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path !== "") root.currentWallpaper = path
      }
    }
  }

  Process {
    id: setProc
    stderr: StdioCollector {
      id: setError
      waitForEnd: true
    }
    onExited: function(exitCode) { root.onSetExited(exitCode) }
  }

  function openRepoPage() {
    folderProc.command = ["xdg-open", root.repoUrl]
    folderProc.running = true
  }

  Process { id: folderProc }

  Timer {
    id: scheduleTimer
    interval: 30000
    running: root.loaded
    repeat: true
    triggeredOnStart: false
    onTriggered: root.reconcile()
  }

  // Periodic light rescan so newly added wallpapers join the pool without a
  // shell restart. Cheap: one find over the configured folder every 10 min.
  Timer {
    interval: 600000
    running: root.loaded
    repeat: true
    onTriggered: if (!catalogProc.running && !cacheProc.running) root.refreshCatalog(false)
  }

  Component.onCompleted: {
    root.nowEpoch = Date.now()
    configDirProcess.running = true
    themeNameFile.path = root.themeNamePath
    root.requestThemeRead()
    root.updateCurrent()
  }
}
