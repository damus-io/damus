var Share = function() {};

Share.prototype = {
  run: function(arguments) {
    arguments.completionFunction({"URL": document.URL, "selectedText": document.getSelection().toString()});
  },
  finalize: function(arguments) {
    // alert shared!
  }
};

var ExtensionPreprocessingJS = new Share
