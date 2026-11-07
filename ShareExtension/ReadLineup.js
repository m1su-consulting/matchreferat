// Runs in Safari when a page is shared to Matchreferat, and only reads Min fotboll.
// Text nodes, not innerText: on a phone the second team's squad is hidden behind a tab.
var ReadLineup = function() {};

ReadLineup.prototype = {
    run: function(page) {
        if (!/(^|\.)svenskfotboll\.se$/.test(location.hostname)) {
            page.completionFunction({ supported: false });
            return;
        }
        var main = document.querySelector("main") || document.body;

        function textLines() {
            var lines = [];
            var walker = document.createTreeWalker(main, NodeFilter.SHOW_TEXT);
            var node;
            while ((node = walker.nextNode())) lines.push(node.nodeValue);
            return lines;
        }

        function squadsShown() {
            return textLines().filter(function(line) { return line.trim() === "Matchtrupp"; }).length >= 2;
        }

        function finish() {
            var names = [];
            main.querySelectorAll("[role=button]").forEach(function(element) {
                var texts = Array.prototype.map.call(element.querySelectorAll("p"), function(p) { return p.textContent.trim(); });
                if (texts.length === 0 || names.length === 2) return;
                // Club, then team: "Björkdalens IF" + "Björkdalens IF P14", or "Ekbacka IK" + "Dam".
                var club = texts[0], team = texts[1];
                names.push(!team ? club : team.indexOf(club.split(" ")[0]) === 0 ? team : club + " " + team);
            });
            // Every tab of a match counts as the same match.
            var game = location.pathname.match(/\/game-view\/\d+/);
            page.completionFunction({ supported: true, names: names, lines: textLines(),
                                           url: location.origin + (game ? game[0] : location.pathname) });
        }

        if (squadsShown()) {
            finish();
            return;
        }
        // The squads are only on the page while the Lineup tab is open, so open it and wait a moment.
        main.querySelectorAll("a, button, [role=tab], li, span").forEach(function(element) {
            if (/^(lineup|line-up|laguppställning)$/i.test(element.textContent.trim())) element.click();
        });
        var waited = 0;
        var timer = setInterval(function() {
            waited += 200;
            if (squadsShown() || waited >= 3000) {
                clearInterval(timer);
                finish();
            }
        }, 200);
    },
    finalize: function(page) {}
};

var ExtensionPreprocessingJS = new ReadLineup;
