import Foundation
import Testing
@testable import ArdiaBrowser

struct HLSPlaylistTests {
  let base = URL(string: "https://cdn.example.com/video/abc/master.m3u8")!

  @Test func parsesMasterWithVariantsAndAudioGroups() throws {
    let text = """
    #EXTM3U
    #EXT-X-VERSION:6
    #EXT-X-INDEPENDENT-SEGMENTS
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud-128",NAME="English",LANGUAGE="en",DEFAULT=YES,AUTOSELECT=YES,CHANNELS="2",URI="audio/en/128.m3u8"
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud-128",NAME="Español",LANGUAGE="es",DEFAULT=NO,AUTOSELECT=YES,CHANNELS="2",URI="audio/es/128.m3u8"
    #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",LANGUAGE="en",URI="subs/en.m3u8"
    #EXT-X-STREAM-INF:BANDWIDTH=800000,AVERAGE-BANDWIDTH=700000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2",FRAME-RATE=29.970,AUDIO="aud-128",SUBTITLES="subs"
    video/360.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2",AUDIO="aud-128"
    https://other.example.com/1080.m3u8?token=a,b
    #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2",AUDIO="aud-128"
    video/720.m3u8
    #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=90000,RESOLUTION=640x360,URI="video/iframes.m3u8"
    """
    let master = try #require(try HLSPlaylist.parse(text, baseURL: base).masterValue)
    #expect(master.variants.count == 3)
    #expect(master.variants[0].uri.absoluteString == "https://cdn.example.com/video/abc/video/360.m3u8")
    #expect(master.variants[0].averageBandwidth == 700000)
    #expect(master.variants[0].frameRate == 29.97)
    #expect(master.variants[0].codecs == ["avc1.4d401e", "mp4a.40.2"])
    #expect(master.variants[1].uri.absoluteString == "https://other.example.com/1080.m3u8?token=a,b")
    #expect(master.renditions.filter { $0.type == "AUDIO" }.count == 2)
    #expect(master.renditions[1].name == "Español")
    #expect(master.renditions[0].channels == 2)

    let selection = try #require(master.bestSelection(preferredLanguages: ["es-MX"]))
    #expect(selection.variant.resolution == HLSResolution(width: 1920, height: 1080))
    #expect(selection.audio?.language == "en")
  }

  @Test func prefersLanguageWhenNoDefaultAudio() throws {
    let text = """
    #EXTM3U
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="English",LANGUAGE="en",AUTOSELECT=YES,URI="en.m3u8"
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="Deutsch",LANGUAGE="de",AUTOSELECT=YES,URI="de.m3u8"
    #EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=320x180,AUDIO="a"
    v.m3u8
    """
    let master = try #require(try HLSPlaylist.parse(text, baseURL: base).masterValue)
    #expect(master.bestSelection(preferredLanguages: ["de-DE"])?.audio?.name == "Deutsch")
    #expect(master.bestSelection(preferredLanguages: ["fr-FR"])?.audio?.name == "English")
  }

  @Test func muxedAudioRenditionWithoutURIMeansNoSeparateTrack() throws {
    let text = """
    #EXTM3U
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="Main",DEFAULT=YES
    #EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=320x180,AUDIO="a"
    v.m3u8
    """
    let master = try #require(try HLSPlaylist.parse(text, baseURL: base).masterValue)
    let selection = try #require(master.bestSelection())
    #expect(selection.audio == nil)
  }

  @Test func skipsUnsavableCodecsAndAudioOnlyVariants() throws {
    let text = """
    #EXTM3U
    #EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"
    audio-only.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=9000000,RESOLUTION=3840x2160,CODECS="vp09.00.50.08,opus"
    vp9.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,CODECS="hvc1.2.4.L123.B0,mp4a.40.2"
    hevc.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2"
    avc.m3u8
    """
    let master = try #require(try HLSPlaylist.parse(text, baseURL: base).masterValue)
    #expect(master.bestSelection()?.variant.uri.lastPathComponent == "hevc.m3u8")
  }

  @Test func prefersAACOverAC3AtTheSameResolution() throws {
    let text = """
    #EXTM3U
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud1",NAME="AAC",DEFAULT=YES,URI="a1.m3u8"
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud2",NAME="AC3",DEFAULT=YES,URI="a2.m3u8"
    #EXT-X-STREAM-INF:BANDWIDTH=8178040,CODECS="avc1.64002a,mp4a.40.2",RESOLUTION=1920x1080,AUDIO="aud1"
    aac.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=8399417,CODECS="avc1.64002a,ac-3",RESOLUTION=1920x1080,AUDIO="aud2"
    ac3.m3u8
    """
    let master = try #require(try HLSPlaylist.parse(text, baseURL: base).masterValue)
    let selection = try #require(master.bestSelection())
    #expect(selection.variant.uri.lastPathComponent == "aac.m3u8")
    #expect(selection.audio?.name == "AAC")
  }

  @Test func parsesMediaPlaylistWithByteRangesKeysAndMap() throws {
    let text = """
    #EXTM3U
    #EXT-X-VERSION:7
    #EXT-X-TARGETDURATION:6
    #EXT-X-MEDIA-SEQUENCE:42
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXT-X-MAP:URI="init.mp4",BYTERANGE="720@0"
    #EXT-X-KEY:METHOD=AES-128,URI="https://keys.example.com/k1",IV=0x0123456789ABCDEF0123456789ABCDEF
    #EXTINF:6.006,
    #EXT-X-BYTERANGE:1000@720
    media.mp4
    #EXTINF:5.5,title
    #EXT-X-BYTERANGE:2000
    media.mp4
    #EXT-X-KEY:METHOD=AES-128,URI="k2"
    #EXT-X-DISCONTINUITY
    #EXTINF:4,
    part3.m4s
    #EXT-X-KEY:METHOD=NONE
    #EXTINF:2,
    part4.m4s
    #EXT-X-ENDLIST
    """
    let media = try #require(try HLSPlaylist.parse(text, baseURL: base).mediaValue)
    #expect(media.segments.count == 4)
    #expect(media.hasEndList)
    #expect(!media.isLive)
    #expect(media.mediaSequence == 42)
    #expect(abs(media.duration - 17.506) < 0.0001)
    #expect(media.usesFragmentedMP4)
    #expect(media.segments[0].map?.byteRange == HLSByteRange(length: 720, offset: 0))
    #expect(media.segments[0].byteRange == HLSByteRange(length: 1000, offset: 720))
    #expect(media.segments[1].byteRange == HLSByteRange(length: 2000, offset: 1720))
    #expect(media.segments[1].byteRange?.httpHeader == "bytes=1720-3719")
    #expect(media.segments[0].key?.method == .aes128)
    #expect(media.segments[0].key?.iv == Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]))
    #expect(media.segments[2].key?.uri?.absoluteString == "https://cdn.example.com/video/abc/k2")
    #expect(media.segments[2].discontinuity)
    #expect(media.segments[2].sequence == 44)
    #expect(media.segments[2].key?.initializationVector(sequence: 44) == Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 44]))
    #expect(media.segments[3].key == nil)
    #expect(!media.isProtected)
  }

  @Test func flagsSampleAESAndFairPlayAsProtected() throws {
    let fairPlay = """
    #EXTM3U
    #EXT-X-TARGETDURATION:6
    #EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://key",KEYFORMAT="com.apple.streamingkeydelivery",KEYFORMATVERSIONS="1"
    #EXTINF:6,
    a.ts
    #EXT-X-ENDLIST
    """
    let media = try #require(try HLSPlaylist.parse(fairPlay, baseURL: base).mediaValue)
    #expect(media.isProtected)

    let session = """
    #EXTM3U
    #EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI="skd://x",KEYFORMAT="com.apple.streamingkeydelivery"
    #EXT-X-STREAM-INF:BANDWIDTH=1
    v.m3u8
    """
    let master = try #require(try HLSPlaylist.parse(session, baseURL: base).masterValue)
    #expect(master.isProtected)
  }

  @Test func liveAndBrokenPlaylists() throws {
    let live = """
    #EXTM3U
    #EXT-X-TARGETDURATION:2
    #EXTINF:2,
    a.ts
    """
    let media = try #require(try HLSPlaylist.parse(live, baseURL: base).mediaValue)
    #expect(media.isLive)
    #expect(throws: HLSParseError.notAPlaylist) { try HLSPlaylist.parse("<html></html>", baseURL: base) }
    #expect(throws: HLSParseError.empty) { try HLSPlaylist.parse("#EXTM3U\n#EXT-X-ENDLIST", baseURL: base) }
    #expect(HLSPlaylist.looksLikePlaylist(Data("\u{FEFF}#EXTM3U\n".utf8)))
    #expect(!HLSPlaylist.looksLikePlaylist(Data([0x47, 0x40, 0x00])))
  }

  @Test func parsesFixturePlaylists() throws {
    let url = try #require(Bundle.module.url(forResource: "master", withExtension: "m3u8", subdirectory: "Fixtures/Video/fmp4"))
    let master = try #require(try HLSPlaylist.parse(String(contentsOf: url, encoding: .utf8), baseURL: url).masterValue)
    let selection = try #require(master.bestSelection())
    #expect(selection.variant.uri.lastPathComponent == "video.m3u8")
    #expect(selection.audio?.uri?.lastPathComponent == "audio.m3u8")
  }
}

struct VideoClassifierTests {
  @Test func classifiesSources() {
    #expect(VideoClassifier.classify(src: "https://v.example.com/clip.mp4") == .file(URL(string: "https://v.example.com/clip.mp4")!))
    #expect(VideoClassifier.classify(src: "https://v.example.com/clip.WEBM?x=1") == .file(URL(string: "https://v.example.com/clip.WEBM?x=1")!))
    #expect(VideoClassifier.classify(src: "https://v.example.com/master.m3u8?sig=1") == .hls(URL(string: "https://v.example.com/master.m3u8?sig=1")!))
    #expect(VideoClassifier.classify(src: "https://v.example.com/play", type: "application/x-mpegURL") == .hls(URL(string: "https://v.example.com/play")!))
    #expect(VideoClassifier.classify(src: "https://v.example.com/manifest.mpd") == .dash)
    #expect(VideoClassifier.classify(src: "blob:https://www.youtube.com/5a1e") == .mediaSource)
    #expect(VideoClassifier.classify(src: "https://v.example.com/clip.mp4", hasMediaKeys: true) == .protected)
    #expect(VideoClassifier.classify(src: "") == .unavailable)
    #expect(VideoClassifier.classify(src: "data:video/mp4;base64,AAAA") == .unavailable)
    let streams = [URL(string: "https://v.example.com/a/master.m3u8")!, URL(string: "https://v.example.com/a/720.m3u8")!]
    #expect(VideoClassifier.classify(src: "blob:https://news.example.com/1", streams: streams) == .hls(streams[0]))
    #expect(VideoClassifier.classify(src: "blob:https://x/1", streams: [URL(string: "https://x/dash/manifest.mpd")!]) == .dash)
  }

  @Test func scanRanksPlayingThenLargestAndExplainsUnsavable() {
    let report = VideoPageReport(pageURL: "https://news.example.com/story", title: "Story", videos: [
      VideoElementReport(index: 0, src: "https://cdn.example.com/small.mp4", visibleArea: 100),
      VideoElementReport(index: 1, src: "https://cdn.example.com/big.mp4", visibleArea: 9000),
      VideoElementReport(index: 2, src: "https://cdn.example.com/playing.m3u8", visibleArea: 50, isPlaying: true),
      VideoElementReport(index: 3, src: "https://cdn.example.com/big.mp4", visibleArea: 10),
      VideoElementReport(index: 4, src: "blob:https://news.example.com/x"),
    ])
    let scan = VideoClassifier.scan(report)
    #expect(scan.savable.map(\.id) == ["video-2", "video-1", "video-0"])
    #expect(scan.unsavable.map(\.kind) == [.mediaSource])

    let youtube = VideoClassifier.scan(VideoPageReport(pageURL: "https://m.youtube.com/watch?v=1", title: "", videos: [
      VideoElementReport(index: 0, src: "blob:https://m.youtube.com/abc", isPlaying: true),
    ]))
    #expect(youtube.savable.isEmpty)
    #expect(youtube.reason == .mediaSource)

    let drm = VideoClassifier.scan(VideoPageReport(pageURL: "https://tv.example.com", title: "", videos: [
      VideoElementReport(index: 0, src: "blob:https://tv.example.com/abc", hasMediaKeys: true),
    ]))
    #expect(drm.reason == .protected)
    #expect(VideoClassifier.scan(VideoPageReport(pageURL: "https://a.com", title: "", videos: [])).reason == .noVideo)
  }

  @Test func scanUsesObservedStreamsAndMetaTags() {
    let hlsJS = VideoClassifier.scan(VideoPageReport(pageURL: "https://news.example.com", title: "", videos: [
      VideoElementReport(index: 0, src: "blob:https://news.example.com/1", isPlaying: true),
    ], streams: ["https://cdn.example.com/hls/master.m3u8", "https://cdn.example.com/hls/1080.m3u8"]))
    #expect(hlsJS.savable.first?.kind == .hls(URL(string: "https://cdn.example.com/hls/master.m3u8")!))

    let native = VideoClassifier.scan(VideoPageReport(pageURL: "https://a.com", title: "", videos: [
      VideoElementReport(index: 0, src: "https://a.com/hls/master.m3u8", visibleArea: 10),
      VideoElementReport(index: 1, src: "blob:https://a.com/2"),
    ], streams: ["https://a.com/hls/master.m3u8"]))
    #expect(native.savable.map(\.kind) == [.hls(URL(string: "https://a.com/hls/master.m3u8")!)])
    #expect(native.unsavable.map(\.kind) == [.mediaSource])

    let meta = VideoClassifier.scan(VideoPageReport(pageURL: "https://a.com", title: "", videos: [], metaVideos: ["https://a.com/v.mp4"]))
    #expect(meta.savable.first?.kind == .file(URL(string: "https://a.com/v.mp4")!))

    let sources = VideoClassifier.scan(VideoPageReport(pageURL: "https://a.com", title: "", videos: [
      VideoElementReport(index: 0, src: "", sources: [VideoSourceReport(src: "https://a.com/v.webm", type: "video/webm")]),
    ]))
    #expect(sources.savable.first?.kind == .file(URL(string: "https://a.com/v.webm")!))
  }
}

extension HLSPlaylist {
  var masterValue: HLSMasterPlaylist? {
    if case .master(let master) = self { return master }
    return nil
  }

  var mediaValue: HLSMediaPlaylist? {
    if case .media(let media) = self { return media }
    return nil
  }
}
