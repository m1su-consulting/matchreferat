// Runs in Safari when a page is shared to Matchreferat, and only reads Min fotboll and Innebandy Play.
var ReadLineup = function() {};

ReadLineup.prototype = {
    run: function(page) {
        var main = document.querySelector("main") || document.body;

        function clickTab(pattern) {
            main.querySelectorAll("a, button, [role=tab], li, span, div").forEach(function(element) {
                if (element.children.length <= 1 && pattern.test(element.textContent.trim())) element.click();
            });
        }

        // Tries every 200 ms for up to three seconds, then goes on with what the page has.
        function waitFor(ready, next) {
            if (ready()) return next();
            var waited = 0;
            var timer = setInterval(function() {
                waited += 200;
                if (ready() || waited >= 3000) {
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
                page.completionFunction({ supported: true, names: names, lines: textLines(),
                                          url: location.origin + (game ? game[0] : location.pathname) });
            }
            // The squads are only on the page while the Lineup tab is open.
            if (!squadsShown()) clickTab(/^(lineup|line-up|laguppställning)$/i);
            waitFor(squadsShown, finish);
        }

        function innebandyPlay() {
            function find(name, root) { return (root || main).querySelector("[class*=" + name + "]"); }
            function roster() {
                var players = [];
                main.querySelectorAll("[class*=LineupPlayers_PlayerItem]").forEach(function(item) {
                    var number = find("LineupPlayers_PlayerNumber", item), name = find("LineupPlayers_PlayerName", item);
                    if (number && name) players.push({ number: number.textContent.trim(), name: name.textContent.trim() });
                });
                return players;
            }
            function teamName() {
                var name = find("LineupWrapper_TeamName");
                return name ? name.textContent.trim() : "";
            }
            function finish(first, second) {
                // The page's title stays empty until you browse inside the site, so the names come from the page.
                var names = Array.prototype.map.call(main.querySelectorAll("[class*=TeamInfoItem_Title]"), function(title) {
                    return title.textContent.trim();
                }).slice(0, 2);
                page.completionFunction({ supported: true, sport: "floorball", names: names, teams: [first, second],
                                          url: location.origin + location.pathname });
            }
            clickTab(/^laguppställning$/i);
            waitFor(function() { return roster().length > 0; }, function() {
                var first = roster(), firstName = teamName();
                var toggles = main.querySelectorAll("[class*=LineupToggle_Link]");
                if (toggles.length < 2) return finish(first, []);
                toggles[1].click();
                waitFor(function() { return teamName() !== firstName && roster().length > 0; }, function() { finish(first, roster()); });
            });
        }

        if (/(^|\.)svenskfotboll\.se$/.test(location.hostname)) {
            minFotboll();
        } else if (location.hostname === "play.innebandy.se") {
            innebandyPlay();
        } else {
            page.completionFunction({ supported: false });
        }
    },
    finalize: function(page) {}
};

var ExtensionPreprocessingJS = new ReadLineup;
