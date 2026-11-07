// Runs in Safari when a page is shared to Matchreferat, and only reads Min fotboll.
// Text nodes, not innerText: on a phone the second team's squad is hidden behind a tab.
var ReadLineup = function() {};

ReadLineup.prototype = {
    run: function(arguments) {
        if (!/(^|\.)svenskfotboll\.se$/.test(location.hostname)) {
            arguments.completionFunction({ supported: false });
            return;
        }
        var main = document.querySelector("main") || document.body;
        var names = [];
        main.querySelectorAll("[role=button]").forEach(function(element) {
            var texts = Array.prototype.map.call(element.querySelectorAll("p"), function(p) { return p.textContent.trim(); });
            if (texts.length === 0 || names.length === 2) return;
            // Club, then team: "Björkdalens IF" + "Björkdalens IF P14", or "Ekbacka IK" + "Dam".
            var club = texts[0], team = texts[1];
            names.push(!team ? club : team.indexOf(club.split(" ")[0]) === 0 ? team : club + " " + team);
        });
        var lines = [];
        var walker = document.createTreeWalker(main, NodeFilter.SHOW_TEXT);
        var node;
        while ((node = walker.nextNode())) lines.push(node.nodeValue);
        arguments.completionFunction({ supported: true, names: names, lines: lines, url: location.href });
    },
    finalize: function(arguments) {}
};

var ExtensionPreprocessingJS = new ReadLineup;
