function emptyStatus() {
  return {
    initialized: false,
    repo: "",
    dirty: false,
    untracked: 0,
    untrackedPaths: [],
    ahead: 0,
    behind: 0,
    lastCommit: ""
  }
}

function parseStatus(text) {
  try {
    var data = JSON.parse(String(text || "{}"))
    if (!data || typeof data !== "object") return emptyStatus()
    return {
      initialized: data.initialized === true,
      repo: String(data.repo || ""),
      dirty: data.dirty === true,
      untracked: parseInt(data.untracked, 10) || 0,
      untrackedPaths: Array.isArray(data.untrackedPaths) ? data.untrackedPaths : [],
      ahead: parseInt(data.ahead, 10) || 0,
      behind: parseInt(data.behind, 10) || 0,
      lastCommit: String(data.lastCommit || "")
    }
  } catch (e) {
    return emptyStatus()
  }
}

function fileUrlToPath(url) {
  var u = String(url || "")
  if (u.indexOf("file://") === 0) u = u.substring(7)
  if (u.charAt(0) !== "/") u = "/" + u
  if (u.length > 1 && u.charAt(u.length - 1) === "/") u = u.substring(0, u.length - 1)
  return u
}

function summaryLine(status) {
  if (!status || !status.initialized) return "Not initialized"
  if (status.untracked > 0) return status.untracked + " unsaved"
  if (status.dirty) return "Uncommitted"
  return "Up to date"
}

if (typeof module !== "undefined") {
  module.exports = {
    emptyStatus: emptyStatus,
    parseStatus: parseStatus,
    fileUrlToPath: fileUrlToPath,
    summaryLine: summaryLine
  }
}
