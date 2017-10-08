(function() {
  var File, SyncHighlight, fs;

  fs = require('fs');

  SyncHighlight = require('./sync_highlight');

  File = (function() {
    function File(name, line) {
      this.name = name;
      this.line = line;
      this.line = parseInt(this.line);
    }

    File.prototype.type = function() {
      if (this.name.match(/coffee$/)) {
        return 'coffee';
      } else {
        return 'js';
      }
    };

    File.prototype.by_lines = function(start, end) {
      if (end == null) {
        end = start;
      }
      return this.content().split('\n').slice(start - 1, end).join('\n');
    };

    File.prototype.length = function() {
      return this.content().split('\n').length || 0;
    };

    File.prototype.content = function() {
      return this._content || (this._content = fs.readFileSync(this.name).toString());
    };

    File.prototype.formatted_content_by_line = function(start, end, line) {
      if (end == null) {
        end = start;
      }
      if (line == null) {
        line = this.line;
      }
      start = (start <= 0 ? 1 : start);
      return new SyncHighlight(this.content(), this.type()).code_snippet(start, end, line);
    };

    return File;

  })();

  module.exports = File;

}).call(this);
