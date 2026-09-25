import Foundation
import Testing
@testable import Altillo

/// Ask's web lookups, routing and sums, none of it touching the network or the model: search pages and forecasts
/// are parsed from fixtures, and the decisions (which route, whether to offer the web) are plain functions.
@MainActor
struct AssistantWebTests {
    private let now = Date(timeIntervalSinceReferenceDate: 812_000_000) // September 2026

    // MARK: - Search results

    @Test func duckDuckGoResultsAreParsedAndAdsSkipped() throws {
        let html = """
        <div class="result results_links"><h2 class="result__title">
        <a rel="nofollow" class="result__a" href="https://www.fcbarcelona.es/es/futbol/primer-equipo/resultados">Resultados - Página Oficial FC Barcelona</a></h2>
        <span>&nbsp; 2026-09-19T00:00:00.0000000</span>
        <a class="result__snippet" href="https://www.fcbarcelona.es/">Página de <b>resultados</b> del Barça &amp; más.</a></div>
        <div class="result"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.laliga.com%2Fclubes%2Ffc%2Dbarcelona&amp;rut=abc">LaLiga</a>
        <a class="result__snippet" href="x">Últimos resultados</a></div>
        <div class="result result--ad"><a class="result__a" href="https://duckduckgo.com/y.js?ad_domain=shop.example">Buy now</a></div>
        """
        let results = AssistantWeb.parseHTMLResults(html)
        #expect(results.count == 2)
        #expect(results[0].title == "Resultados - Página Oficial FC Barcelona")
        #expect(results[0].snippet == "Página de resultados del Barça & más.")
        #expect(results[0].date == "2026-09-19")
        #expect(results[1].url.absoluteString == "https://www.laliga.com/clubes/fc-barcelona", "the redirect is unwrapped")
    }

    @Test func liteAndBingResultsAreParsedToo() throws {
        let lite = """
        <td><a rel="nofollow" href="https://www.marca.com/futbol/barcelona.html" class='result-link'>FC Barcelona | MARCA</a></td>
        <tr><td class='result-snippet'>Toda la actualidad del <b>Barça</b>.</td></tr>
        <span class='timestamp'>2026-09-24T00:00:00.0000000</span>
        """
        let liteResults = AssistantWeb.parseLiteResults(lite)
        #expect(liteResults.count == 1)
        #expect(liteResults.first?.url.host() == "www.marca.com")
        #expect(liteResults.first?.snippet == "Toda la actualidad del Barça.")
        #expect(liteResults.first?.date == "2026-09-24")

        let target = Data("https://coinmarketcap.com/currencies/bitcoin/".utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let bing = """
        <li class="b_algo"><h2><a href="https://www.bing.com/ck/a?!&amp;&amp;p=1&amp;u=a1\(target)&amp;ntb=1" h="x">Bitcoin price today</a></h2>
        <div class="b_caption"><p class="b_lineclamp2">The live Bitcoin price today is $83,910.03 USD.</p></div></li>
        """
        let bingResults = AssistantWeb.parseBingResults(bing)
        #expect(bingResults.first?.url.absoluteString == "https://coinmarketcap.com/currencies/bitcoin/")
        #expect(bingResults.first?.snippet == "The live Bitcoin price today is $83,910.03 USD.")
    }

    @Test func theBotCheckIsRecognised() {
        #expect(AssistantWeb.isBotCheck("<div class=\"anomaly-modal__title\">Unfortunately, bots use DuckDuckGo too.</div>"))
        #expect(!AssistantWeb.isBotCheck("<a class=\"result__a\" href=\"https://apple.com\">Apple</a>"))
    }

    @Test func theSearchIsFormEncodedAsASCII() {
        #expect(AssistantWeb.formEncoded(["q": "último partido del Barça"]) == "q=%C3%BAltimo%20partido%20del%20Bar%C3%A7a")
        let url = AssistantWeb.browserSearchURL("¿Cómo quedó el Barça?")
        #expect(url?.host() == "duckduckgo.com")
        #expect(url?.query()?.contains("Bar%C3%A7a") == true)
    }

    @Test func socialAndScriptOnlySitesAreNotRead() throws {
        #expect(!AssistantWeb.isReadable(try #require(URL(string: "https://www.youtube.com/watch?v=1"))))
        #expect(!AssistantWeb.isReadable(try #require(URL(string: "https://example.com/report.pdf"))))
        #expect(AssistantWeb.isReadable(try #require(URL(string: "https://www.fcbarcelona.es/resultados"))))
        #expect(AssistantWeb.domain(of: try #require(URL(string: "https://www.fcbarcelona.es/x"))) == "fcbarcelona.es")
    }

    // MARK: - Reading pages

    @Test func pagesLoseScriptsMenusAndTags() {
        let html = """
        <html><head><title>T</title><style>p { color: red }</style></head><body>
        <nav><a href="/">Home</a> <a href="/menu">Menu</a></nav>
        <script>var secret = "<p>not text</p>";</script>
        <!-- a comment <p>hidden</p> -->
        <p>Sevilla <b>1</b> - <b>3</b> FC&nbsp;Barcelona &amp; more&#33; &aacute;&#xE9;</p>
        <div>Second<br/>line</div>
        <footer>© Footer</footer></body></html>
        """
        let lines = AssistantHTML.cleanLines(AssistantHTML.text(fromHTML: html))
        #expect(lines.contains("Sevilla 1 - 3 FC Barcelona & more! áé"))
        #expect(lines.contains("Second") && lines.contains("line"))
        #expect(!lines.joined().contains("Menu"))
        #expect(!lines.joined().contains("secret"))
        #expect(!lines.joined().contains("hidden"))
        #expect(!lines.joined().contains("Footer"))
    }

    @Test func theMainPartIsPreferredWhenItHasText() {
        let prose = String(repeating: "The match ended with a late goal from the visitors. ", count: 10)
        let html = "<body><div>Sidebar junk</div><main id=\"main\"><p>\(prose)</p></main></body>"
        let lines = AssistantHTML.readableLines(html)
        #expect(!lines.joined().contains("Sidebar"))
        #expect(!lines.joined().contains("id="), "the tag's attributes never leak into the text")
        #expect(lines.joined().contains("late goal"))
    }

    @Test func theExcerptKeepsWhatMatchesTheQuery() {
        let lines = ["Culers", "Login", "Menu", "Primer equipo", "Resultados", "sáb 19 sept", "La Liga", "Jornada 7",
                     "Sevilla", "1", "-", "3", "FC Barcelona"]
            + Array(repeating: "Tienda oficial de camisetas y regalos para toda la familia culé, envío gratis", count: 20)
        let excerpt = AssistantHTML.excerpt(
            lines: lines, terms: AssistantHTML.terms(in: "resultado último partido FC Barcelona"), limit: 400
        )
        #expect(excerpt.contains("Sevilla 1 - 3 FC Barcelona"))
        #expect(excerpt.count <= 400)
        #expect(AssistantHTML.terms(in: "¿Cómo quedó el último partido del Barça?") == ["quedo", "partido", "barca"])
    }

    @Test func theDigestPutsPagesFirstAndFitsTheBudget() throws {
        let results = (1...6).map { index in
            AssistantWeb.Result(
                title: "Result \(index) " + String(repeating: "long title ", count: 20),
                url: URL(string: "https://site\(index).example/page")!,
                snippet: String(repeating: "snippet words ", count: 40),
                date: index == 1 ? "2026-09-19" : nil
            )
        }
        let page = (results[0], ["Sevilla 1 - 3 FC Barcelona"] + Array(repeating: String(repeating: "filler ", count: 60), count: 30))
        let text = AssistantWeb.digestText(query: "Barça result", results: results, pages: [page], terms: ["barcelona"])
        #expect(text.count <= AssistantContent.toolOutputLimit)
        #expect(text.hasPrefix("From site1.example:"))
        #expect(text.contains("Sevilla 1 - 3 FC Barcelona"))
        #expect(text.contains("1. Result 1"))
        #expect(!text.contains("5. Result 5"), "four results are listed at most")
        #expect(text.contains("2026-09-19"))
        #expect(AssistantWeb.digestText(query: "nothing", results: [], pages: [], terms: []).contains("found nothing"))
    }

    // MARK: - Weather

    @Test func weatherQuestionsNameTheirPlace() {
        #expect(AssistantWeather.place(in: "What's the weather in Barcelona today?") == "Barcelona")
        #expect(AssistantWeather.place(in: "tiempo en Sant Cugat mañana") == "Sant Cugat")
        #expect(AssistantWeather.place(in: "Quin temps farà demà a Girona?") == "Girona")
        #expect(AssistantWeather.place(in: "weather") == "")
        #expect(AssistantWeather.place(in: "¿Cuánto tiempo tarda el AVE a Madrid?") == nil)
        #expect(AssistantWeather.place(in: "FC Barcelona last match result") == nil)
    }

    @Test func theForecastReadsLikeAReport() throws {
        let json = """
        {"timezone":"Europe/Madrid","current":{"time":"2026-09-24T09:00","temperature_2m":20.4,"apparent_temperature":21.2,
        "relative_humidity_2m":71,"weather_code":0,"wind_speed_10m":5.8,"precipitation":0},
        "daily":{"time":["2026-09-24","2026-09-25","2026-09-26"],"weather_code":[3,2,61],
        "temperature_2m_max":[28.1,29,27],"temperature_2m_min":[19,20.2,20],"precipitation_probability_max":[0,10,null]}}
        """
        let forecast = try JSONDecoder().decode(AssistantWeather.ForecastResponse.self, from: Data(json.utf8))
        let report = AssistantWeather.report(forecast, place: "Barcelona, Catalonia, Spain", guessed: false, imperial: false)
        #expect(report.contains("Weather for Barcelona, Catalonia, Spain"))
        #expect(report.contains("Now (09:00 local): 20°C, clear sky, feels like 21°C, humidity 71%, wind 6 km/h."))
        #expect(report.contains("Today (2026-09-24): overcast, 19–28°C, 0% chance of rain."))
        #expect(report.contains("Day after tomorrow (2026-09-26): light rain, 20–27°C."))
        let guessed = AssistantWeather.report(forecast, place: "Madrid, Spain", guessed: true, imperial: true)
        #expect(guessed.hasPrefix("No place was given"))
        #expect(guessed.contains("°F") && guessed.contains("mph"))
    }

    // MARK: - Routing

    @Test func questionsAreRoutedToWhatTheyNeed() {
        #expect(AssistantRouter.route("Write a haiku about autumn.", now: now) == .chat)
        #expect(AssistantRouter.route("Translate 'good morning' into Italian.", now: now) == .chat)
        #expect(AssistantRouter.route("Who wrote One Hundred Years of Solitude?", now: now) == .chat)
        #expect(AssistantRouter.route("What do I have today?", now: now) == .context)
        #expect(AssistantRouter.route("¿Qué tengo mañana?", now: now) == .context)
        #expect(AssistantRouter.route("Summarize “Informe.pdf” from my shelf.", now: now) == .context)
        #expect(AssistantRouter.route("What's playing in Spotify?", now: now) == .context)
        #expect(AssistantRouter.route("Explain what I copied.", now: now) == .context)
        #expect(AssistantRouter.route("¿Cómo quedó el último partido del Barça?", now: now) == .live)
        #expect(AssistantRouter.route("What's the weather in Barcelona today?", now: now) == .live)
        #expect(AssistantRouter.route("Who won the Tour de France 2026?", now: now) == .live)
        #expect(AssistantRouter.route("And tomorrow?", followsContext: true, now: now) == .context)
        #expect(AssistantRouter.route("And tomorrow?", followsContext: false, now: now) == .chat)
    }

    @Test func theWebIsOfferedOnlyWhenTheAnswerNeededIt() {
        #expect(AssistantLiveness.answerAdmitsNotKnowing("I can't check live data, but Barça usually wins at home."))
        #expect(AssistantLiveness.answerAdmitsNotKnowing("No puedo consultar resultados en tiempo real."))
        #expect(AssistantLiveness.answerAdmitsNotKnowing("I’m not sure who won."))
        #expect(!AssistantLiveness.answerAdmitsNotKnowing("Gabriel García Márquez wrote it in 1967."))

        #expect(AssistantLiveness.shouldOffer(question: "Who won the last F1 race?", answer: "Max Verstappen.", usedLocalTools: false, now: now))
        #expect(!AssistantLiveness.shouldOffer(question: "What did I copy last?", answer: "A tracking number.", usedLocalTools: true, now: now))
        #expect(!AssistantLiveness.shouldOffer(question: "Write a haiku", answer: "Leaves fall…", usedLocalTools: false, now: now))
        #expect(AssistantLiveness.shouldOffer(question: "What is the capital of Peru?", answer: "I don't know.", usedLocalTools: false, now: now))
    }

    // MARK: - Sums

    @Test func sumsAreWorkedOutExactly() {
        #expect(AssistantCalculator.evaluate("2340 * 17%") == 397.8)
        #expect(AssistantCalculator.evaluate("(1250 + 80) / 4") == 332.5)
        #expect(AssistantCalculator.evaluate("200 + 10%") == 220)
        #expect(AssistantCalculator.evaluate("2^10") == 1024)
        #expect(AssistantCalculator.evaluate("-3 + sqrt(16)") == 1)
        #expect(AssistantCalculator.evaluate("12 ÷ 4 × 3") == 9)
        #expect(AssistantCalculator.evaluate("1 / 0") == nil)
        #expect(AssistantCalculator.evaluate("hello") == nil)
        #expect(AssistantCalculator.evaluate("(2 + 3") == nil)
        #expect(AssistantCalculator.format(397.8) == "397.8")
        #expect(AssistantCalculator.format(1024) == "1024")
        #expect(AssistantCalculator.format(1.0 / 3.0) == "0.3333333333")
    }

    @Test func sumsInAQuestionComeWithTheirResult() {
        #expect(AssistantCalculator.hint(for: "¿Cuánto es el 21% de 1.250 €?") == "21% of 1250 = 262.5")
        #expect(AssistantCalculator.hint(for: "What's 17% of 2,340?") == "17% of 2340 = 397.8")
        #expect(AssistantCalculator.hint(for: "How much is (1250 + 80) / 4 each?") == "(1250+80)/4 = 332.5")
        #expect(AssistantCalculator.hint(for: "Split 3 x 45,50 between us") == "3*45.50 = 136.5")
        #expect(AssistantCalculator.hint(for: "Write a haiku about 2026") == nil)
        #expect(AssistantCalculator.hint(for: "Meet at 10:30 on 24-09") == nil)
        #expect(AssistantCalculator.hint(for: "What happened on 2026-09-24?") == nil)
        #expect(AssistantCalculator.hint(for: "What's 10-3?") == "10-3 = 7")
    }

    // MARK: - Instructions and prompts

    @Test func eachRouteGetsShortInstructions() {
        let chat = AssistantInstructions.text(now: now, route: .chat)
        let context = AssistantInstructions.text(now: now, route: .context)
        let live = AssistantInstructions.text(now: now, route: .live)
        #expect(chat.contains("can't check live data"), "admitting it is what triggers the web offer")
        #expect(chat.contains("Don't refuse"))
        #expect(context.contains("shelf, calendar, nowPlaying, clipboard, usage or agents"))
        #expect(live.contains("web results"))
        for text in [chat, context, live] {
            #expect(text.count < 800, "instructions are paid for on every question")
            #expect(text.contains("2026"))
        }
        #expect(AssistantTools.all(for: .chat, shelfItems: { [] }, report: { _ in }).isEmpty)
        #expect(AssistantTools.all(for: .live, shelfItems: { [] }, report: { _ in }).isEmpty)
        #expect(AssistantTools.all(for: .context, shelfItems: { [] }, report: { _ in }).map(\.name)
            == ["shelf", "calendar", "nowPlaying", "clipboard", "usage", "agents"])
    }

    @Test func webResultsTravelWithTheQuestion() {
        let prompt = AssistantInstructions.prompt(for: "¿Cómo quedó el último partido del Barça?", webResults: "From fcbarcelona.es:\nSevilla 1 - 3 FC Barcelona")
        #expect(prompt.hasPrefix("Question: ¿Cómo quedó el último partido del Barça?"))
        #expect(prompt.contains("Sevilla 1 - 3 FC Barcelona"))
        #expect(prompt.hasSuffix("(Reply in Spanish.)"))
        let offline = AssistantInstructions.prompt(forOfflineLive: "Who won the last F1 race?")
        #expect(offline.contains("no made-up results"))
    }

    // MARK: - The store's web actions

    @Test func openingInTheBrowserSendsNothingItself() {
        let store = AssistantStore()
        var opened: [URL] = []
        var allowed = false
        store.context.openURL = { opened.append($0) }
        store.context.allowWebSearch = { allowed = true }
        store.context.webSearchAllowed = { allowed }
        let exchange = AssistantStore.Exchange(question: "¿Cómo quedó el Barça?", answer: "No puedo consultarlo.", status: .done, offersWeb: true)

        store.openInBrowser(exchange)
        #expect(opened.first?.host() == "duckduckgo.com")
        #expect(!allowed)

        store.open(AssistantWebSource(url: URL(string: "https://www.fcbarcelona.es/")!, title: "FC Barcelona"))
        #expect(opened.last?.host() == "www.fcbarcelona.es")

        store.alwaysAllowWeb(for: exchange)
        #expect(allowed, "“Always allow” turns the setting on")
    }

    @Test func webSourcesShowTheirDomain() throws {
        let source = AssistantWebSource(url: try #require(URL(string: "https://www.laliga.com/clubes")), title: "LaLiga")
        #expect(source.domain == "laliga.com")
        #expect(AssistantActivity.web.symbol == "globe")
        #expect(!AssistantActivity.web.isLocalContext && AssistantActivity.calendar.isLocalContext)
        #expect(AssistantFailure.tool("web").message.contains("web"))
    }
}
