// Runs in Safari when a page is shared to Matchreferat, and only reads Min fotboll and Innebandy Play.
var ReadLineup = function() {};

ReadLineup.prototype = {
    run: function(page) {
        var main = document.querySelector("main") || document.body;

        function clickTab(pattern) {
            var clicked = false;
            main.querySelectorAll("a, button, [role=tab], li, span, div").forEach(function(element) {
                if (element.children.length <= 1 && pattern.test(element.textContent.trim())) {
                    element.click();
                    clicked = true;
                }
            });
            return clicked;
        }

        // Tries every 200 ms for up to a second, then goes on with what the page has.
        // Safari throws away the result of a script that takes too long: three seconds is too long.
        function waitFor(ready, next) {
            if (ready()) return next();
            var waited = 0;
            var timer = setInterval(function() {
                waited += 200;
                if (ready() || waited >= 1000) {
                    clearInterval(timer);
                    next();
                }
            }, 200);
        }

        function minFotboll() {
            // Text nodes, not innerText: on a phone the second team's squad is hidden behind a tab.
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
                // Logged in, the Feed tab lists "Datum" and "Tid", each followed by its value. Otherwise the
                // header shows only the time between the teams, "17:00", until the match has a score.
                // The whole line must end in the time, so a team called "P2014:17" isn't read as one.
                var shown = textLines().map(function(line) { return line.trim(); }).filter(Boolean);
                function after(label) {
                    var index = shown.indexOf(label);
                    return index >= 0 && index + 1 < shown.length ? shown[index + 1] : "";
                }
                var headerTime = shown.filter(function(line) {
                    return line.length < 30 && /(^|\s)\d{1,2}[:.]\d{2}$/.test(line);
                })[0] || "";
                var kickoff = (after("Datum") + " " + (after("Tid") || headerTime)).trim() || undefined;
                page.completionFunction({ supported: true, names: names, lines: textLines(), kickoff: kickoff,
                                          url: location.origin + (game ? game[0] : location.pathname) });
            }
            // The squads are only on the page while the Lineup tab is open.
            // Without a tab to open there is nothing to wait for: the match is saved and the squads come later.
            if (squadsShown() || !clickTab(/^(lineup|line-up|laguppställning)$/i)) return finish();
            waitFor(squadsShown, finish);
        }

        if (/(^|\.)svenskfotboll\.se$/.test(location.hostname)) {
            minFotboll();
        } else if (location.hostname === "play.innebandy.se") {
            // The pages are public, so the extension opens them itself.
            page.completionFunction({ supported: true, sport: "floorball", url: location.href });
        } else {
            page.completionFunction({ supported: false });
        }
    },
    finalize: function(page) {}
};

var ExtensionPreprocessingJS = new ReadLineup;
