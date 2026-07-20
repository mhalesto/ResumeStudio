/*
 Runs inside Safari, in the page the user chose to share, and hands what it
 finds back to the share extension.

 This is the only way to read a posting that sits behind a sign-in: it runs in
 the reader's own logged-in session, on a page they are looking at and have
 explicitly shared. Nothing is fetched, crawled or followed — the reach is one
 page, chosen by the user, at the moment they ask for it.

 Boards publish the posting itself as schema.org JobPosting for search engines,
 so that is tried first: it is structured, stable, and meant to be read by
 machines. The visible text is only the fallback for sites that publish none.
*/
var ExtensionPreprocessingJS = new function () {
  /** The schema.org JobPosting a page declares for search engines, if any. */
  function structuredPosting() {
    var blocks = document.querySelectorAll('script[type="application/ld+json"]');
    for (var i = 0; i < blocks.length; i++) {
      try {
        var posting = findPosting(JSON.parse(blocks[i].textContent));
        if (posting) return JSON.stringify(posting);
      } catch (error) {
        // A malformed block on the page is not a reason to give up on the rest.
      }
    }
    return "";
  }

  /** JSON-LD nests: a posting can sit in an array, or under @graph. */
  function findPosting(node) {
    if (!node || typeof node !== "object") return null;
    if (Array.isArray(node)) {
      for (var i = 0; i < node.length; i++) {
        var found = findPosting(node[i]);
        if (found) return found;
      }
      return null;
    }
    var type = node["@type"];
    if (type === "JobPosting") return node;
    if (Array.isArray(type) && type.indexOf("JobPosting") !== -1) return node;
    if (node["@graph"]) return findPosting(node["@graph"]);
    return null;
  }

  /** What the page actually shows, with the furniture left out. */
  function readableText() {
    var scope =
      document.querySelector("main") ||
      document.querySelector("article") ||
      document.body;
    if (!scope) return "";
    var clone = scope.cloneNode(true);
    var noise = clone.querySelectorAll("script, style, noscript, nav, header, footer, svg");
    for (var i = 0; i < noise.length; i++) {
      if (noise[i].parentNode) noise[i].parentNode.removeChild(noise[i]);
    }
    var text = clone.innerText || clone.textContent || "";
    // Runs of blank lines are most of the bulk on a job board, and none of the
    // meaning. A ceiling keeps a sprawling page from filling the payload.
    return text.replace(/[ \t]+/g, " ").replace(/\n\s*\n\s*\n+/g, "\n\n").trim().slice(0, 40000);
  }

  function metaContent(selector) {
    var tag = document.querySelector(selector);
    return (tag && tag.getAttribute("content")) || "";
  }

  this.run = function (arguments) {
    arguments.completionFunction({
      url: document.URL,
      title: document.title || metaContent('meta[property="og:title"]'),
      posting: structuredPosting(),
      text: readableText()
    });
  };
};
