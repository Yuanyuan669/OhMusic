import webview from '@ohos.web.webview';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import media from '@ohos.multimedia.media';
import mediaLibrary from '@ohos.multimedia.mediaLibrary';
import common from '@ohos.app.ability.common';
import { BusinessError } from '@ohos.base';

interface PageEvent {
  url: string;
}

interface ProgressEvent {
  newProgress: number;
}

interface TitleEvent {
  title: string;
}

interface ErrorEvent {
  request: WebResourceRequest;
  error: WebResourceError;
}

interface LoadInterceptEvent {
  data: WebResourceRequest;
}

const HOME_URL: string = 'https://music.163.com/st/webplayer';
const SEARCH_URL: string = 'https://music.163.com/#/search';
const UA_MOBILE: string = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

class LocalTrack {
  name: string;
  size: number;
  asset: mediaLibrary.FileAsset;

  constructor(name: string, size: number, asset: mediaLibrary.FileAsset) {
    this.name = name;
    this.size = size;
    this.asset = asset;
  }
}

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State title: string = '网易云音乐';
  @State progress: number = 0;
  @State loading: boolean = false;
  @State canBack: boolean = false;
  @State canForward: boolean = false;
  @State errText: string = '';
  @State isLocal: boolean = false;
  @State localName: string = '未选择音频';
  @State localStatus: string = '';
  @State localPlaying: boolean = false;
  @State localReady: boolean = false;
  @State localTracks: Array<LocalTrack> = [];
  @State currentIndex: number = -1;
  @State playPos: number = 0;
  @State duration: number = 0;
  private player: media.AVPlayer | null = null;
  private audioFile: fs.File | null = null;
  private libFd: number = -1;
  private pendingFd: number = -1;
  private pendingSize: number = 0;

  aboutToAppear(): void {
    const launchUrl = AppStorage.get<string>('launchUrl');
    if (launchUrl !== undefined && launchUrl.length > 0) {
      setTimeout(() => {
        this.loadUrl(launchUrl);
      }, 300);
    }
  }

  aboutToDisappear(): void {
    if (this.player !== null) {
      this.player.release();
      this.player = null;
    }
    if (this.audioFile !== null) {
      fs.closeSync(this.audioFile);
      this.audioFile = null;
    }
    if (this.libFd >= 0) {
      fs.closeSync(this.libFd);
      this.libFd = -1;
    }
  }

  private applyPending(): void {
    if (this.player === null || this.pendingFd < 0) {
      return;
    }
    const fd = this.pendingFd;
    const size = this.pendingSize;
    this.pendingFd = -1;
    this.pendingSize = 0;
    try {
      this.player.fdSrc = { fd: fd, offset: 0, length: size };
    } catch (e) {
      const err = e as BusinessError;
      this.localStatus = '设置音源失败：' + err.code + ' ' + err.message;
    }
  }

  private async ensurePlayer(): Promise<media.AVPlayer> {
    if (this.player === null) {
      this.player = await media.createAVPlayer();
      this.player.on('stateChange', (state: media.AVPlayerState) => {
        if (state === 'initialized') {
          this.player?.prepare();
        } else if (state === 'idle') {
          this.applyPending();
        } else if (state === 'prepared') {
          this.localReady = true;
          this.localStatus = '已就绪';
          this.duration = this.player?.duration ?? 0;
          this.player?.play();
        } else if (state === 'playing') {
          this.localPlaying = true;
          this.localStatus = '播放中';
        } else if (state === 'paused') {
          this.localPlaying = false;
          this.localStatus = '已暂停';
        } else if (state === 'stopped' || state === 'completed') {
          this.localPlaying = false;
          this.localStatus = '已停止';
          if (state === 'completed') {
            this.playPos = this.duration;
          }
        }
      });
      this.player.on('timeUpdate', (time: number) => {
        this.playPos = time;
        if (this.duration <= 0 && this.player !== null) {
          this.duration = this.player.duration;
        }
      });
      this.player.on('error', (err: BusinessError) => {
        this.localPlaying = false;
        this.localStatus = '播放失败：' + err.code + ' ' + err.message;
      });
    }
    return this.player;
  }

  private async loadAudioFile(uri: string, displayName: string): Promise<void> {
    let file: fs.File;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    } catch (e) {
      const err = e as BusinessError;
      this.localStatus = '打开文件失败：' + err.code + ' ' + err.message;
      return;
    }
    if (this.audioFile !== null) {
      fs.closeSync(this.audioFile);
    }
    this.audioFile = file;
    const stat = fs.statSync(file.fd);
    this.localName = displayName;
      this.localStatus = '加载中';
    this.localReady = false;
    try {
      const player = await this.ensurePlayer();
      this.pendingFd = file.fd;
      this.pendingSize = stat.size;
      player.reset();
      if (player.state === 'idle') {
        this.applyPending();
      }
    } catch (e) {
      const err = e as BusinessError;
      this.localStatus = '播放器初始化失败：' + err.code + ' ' + err.message;
    }
  }

  private formatTime(ms: number): string {
    const total = Math.floor(ms / 1000);
    const m = Math.floor(total / 60);
    const s = total % 60;
    return (m < 10 ? '0' + m : '' + m) + ':' + (s < 10 ? '0' + s : '' + s);
  }

  private async playTrack(index: number): Promise<void> {
    if (index < 0 || index >= this.localTracks.length) {
      return;
    }
    const track = this.localTracks[index];
    try {
      const fd = await track.asset.open('r');
      if (this.audioFile !== null) {
        fs.closeSync(this.audioFile);
        this.audioFile = null;
      }
      if (this.libFd >= 0) {
        fs.closeSync(this.libFd);
      }
      this.libFd = fd;
      this.currentIndex = index;
      this.localName = track.name;
    this.localStatus = '加载中';
      this.localReady = false;
      this.playPos = 0;
      this.duration = 0;
      const player = await this.ensurePlayer();
      this.pendingFd = fd;
      this.pendingSize = track.size;
      player.reset();
      if (player.state === 'idle') {
        this.applyPending();
      }
    } catch (e) {
      const err = e as BusinessError;
      this.localStatus = '打开失败：' + err.code + ' ' + err.message;
    }
  }

  private seekTo(value: number): void {
    if (this.player === null || !this.localReady) {
      return;
    }
    const wasPlaying = this.localPlaying;
    const target = Math.floor(value);
    try {
      this.player.seek(target);
      this.playPos = target;
      if (wasPlaying) {
        setTimeout(() => {
          if (this.player !== null) {
            this.player.play();
          }
        }, 150);
      }
    } catch (e) {
      console.error('seek failed');
    }
  }

  private async scanLibrary(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const ml = mediaLibrary.getMediaLibrary(ctx);
      const options: mediaLibrary.MediaFetchOptions = {
        selections: mediaLibrary.FileKey.MEDIA_TYPE + '=?',
        selectionArgs: [mediaLibrary.MediaType.AUDIO.toString()]
      };
      const result = await ml.getFileAssets(options);
      const assets = await result.getAllObject();
      if (assets.length === 0) {
        this.localStatus = '媒体库没有音频文件';
        return;
      }
      const tracks: Array<LocalTrack> = [];
      for (let i = 0; i < assets.length; i++) {
        tracks.push(new LocalTrack(assets[i].displayName, assets[i].size, assets[i]));
      }
      this.localTracks = tracks;
      this.localStatus = '媒体库 ' + tracks.length + ' 首';
      await this.playTrack(0);
    } catch (e) {
      const err = e as BusinessError;
      this.localStatus = '扫描失败：' + err.code + ' ' + err.message;
    }
  }

  private async pickAudio(): Promise<void> {
    try {
      const audioPicker = new picker.AudioViewPicker();
      const uris = await audioPicker.select();
      if (uris.length === 0) {
        return;
      }
      const uri = uris[0];
      const segs = uri.split('/');
      await this.loadAudioFile(uri, decodeURIComponent(segs[segs.length - 1]));
    } catch (e) {
      const err = e as BusinessError;
      this.localStatus = '选择失败：' + err.code + ' ' + err.message;
    }
  }

  private toggleLocal(): void {
    if (this.player === null || !this.localReady) {
      return;
    }
    if (this.localPlaying) {
      this.player.pause();
    } else {
      this.player.play();
    }
  }

  private stopLocal(): void {
    if (this.player !== null && this.localReady) {
      this.player.stop();
    }
  }

  private loadUrl(url: string): void {
    try {
      this.controller.loadUrl(url);
    } catch (e) {
      this.errText = '页面加载失败';
    }
  }

  private goHome(): void {
    this.loadUrl(HOME_URL);
  }

  private goSearch(): void {
    this.loadUrl(SEARCH_URL);
  }

  private refresh(): void {
    try {
      if (this.loading) {
        this.controller.stop();
        this.loading = false;
      } else {
        this.controller.refresh();
      }
    } catch (e) {
      this.errText = '刷新失败';
    }
  }

  private updateNav(): void {
    try {
      this.canBack = this.controller.accessBackward();
      this.canForward = this.controller.accessForward();
    } catch (e) {
      this.canBack = false;
      this.canForward = false;
    }
  }

  private blockedScheme(url: string): boolean {
    const lower = url.toLowerCase();
    return lower.startsWith('orpheus://') || lower.startsWith('netease-music://') ||
      lower.startsWith('neteasemusic://') || lower.startsWith('intent://') ||
      lower.startsWith('weixin://') || lower.startsWith('alipays://') ||
      lower.startsWith('bilibili://');
  }

  onBackPress(): boolean {
    if (this.canBack) {
      try {
        this.controller.backward();
        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  @Builder
  NavButton(icon: string, label: string, enabled: boolean, action: () => void) {
    Column({ space: 1 }) {
      Text(icon)
        .fontSize(20)
        .fontColor(enabled ? '#FFFFFF' : '#666666')
        .height(24)
      Text(label)
        .fontSize(10)
        .fontColor(enabled ? '#BBBBBB' : '#555555')
    }
    .width('20%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (enabled) {
        action();
      }
    })
  }

  build() {
    Column() {
      Row() {
        Button('在线')
          .fontSize(14)
          .fontColor(this.isLocal ? '#666666' : '#FFFFFF')
          .backgroundColor(this.isLocal ? '#FFFFFF' : '#EC4141')
          .height(34)
          .layoutWeight(1)
          .onClick(() => {
            this.isLocal = false;
          })
        Button('本地')
          .fontSize(14)
          .fontColor(this.isLocal ? '#FFFFFF' : '#666666')
          .backgroundColor(this.isLocal ? '#EC4141' : '#FFFFFF')
          .height(34)
          .layoutWeight(1)
          .onClick(() => {
            this.isLocal = true;
          })
      }
      .width('100%')
      .height(46)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#FFFFFF')

      if (!this.isLocal && this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color('#EC4141')
          .backgroundColor('#F1F1F1')
      }

      Stack({ alignContent: Alignment.TopStart }) {
        Web({ src: HOME_URL, controller: this.controller })
          .width('100%')
          .height('100%')
          .visibility(this.isLocal ? Visibility.Hidden : Visibility.Visible)
          .domStorageAccess(true)
          .fileAccess(false)
          .javaScriptAccess(true)
          .darkMode(WebDarkMode.Off)
          .forceDarkAccess(false)
          .onControllerAttached(() => {
            try {
              this.controller.setCustomUserAgent(UA_MOBILE);
            } catch (e) {
              console.error('ua failed');
            }
          })
          .onLoadIntercept((event: LoadInterceptEvent) => {
            try {
              const url = event.data.getRequestUrl();
              if (this.blockedScheme(url)) {
                return true;
              }
            } catch (e) {
              return false;
            }
            return false;
          })
          .onPageBegin((event?: PageEvent) => {
            this.loading = true;
            this.progress = 0;
            this.errText = '';
          })
          .onPageEnd((event?: PageEvent) => {
            this.loading = false;
            this.progress = 100;
            this.updateNav();
          })
          .onProgressChange((event?: ProgressEvent) => {
            this.progress = event !== undefined ? event.newProgress : 0;
            if (this.progress >= 100) {
              this.loading = false;
            }
            this.updateNav();
          })
          .onTitleReceive((event?: TitleEvent) => {
            if (event !== undefined && event.title.length > 0) {
              this.title = event.title;
            }
          })
          .onErrorReceive((event?: ErrorEvent) => {
            if (event === undefined) {
              return;
            }
            try {
              if (!event.request.isMainFrame()) {
                return;
              }
              this.loading = false;
              this.errText = '加载失败：' + event.error.getErrorCode() + ' ' + event.error.getErrorInfo();
            } catch (e) {
              this.errText = '页面加载失败';
            }
          })

        if (this.isLocal) {
          Column({ space: 10 }) {
            Row() {
              Text('本地播放')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#222222')
                .layoutWeight(1)
              Button('扫描媒体库')
                .fontSize(12)
                .height(30)
                .backgroundColor('#F2F2F2')
                .fontColor('#222222')
                .onClick(() => {
                  this.scanLibrary();
                })
            }
            .width('100%')

            Text(this.localName)
              .fontSize(14)
              .fontColor('#444444')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            Slider({
              value: this.playPos,
              min: 0,
              max: this.duration > 0 ? this.duration : 1,
              step: 1
            })
              .width('100%')
              .selectedColor('#EC4141')
              .blockColor('#EC4141')
              .onChange((value: number) => {
                this.seekTo(value);
              })

            Row() {
              Text(this.formatTime(this.playPos))
                .fontSize(11)
                .fontColor('#999999')
              Blank()
              Text(this.formatTime(this.duration))
                .fontSize(11)
                .fontColor('#999999')
            }
            .width('100%')

            Row({ space: 12 }) {
              Button(this.localPlaying ? '暂停' : '播放')
                .height(34)
                .backgroundColor('#EC4141')
                .fontColor(this.localReady ? '#FFFFFF' : '#F2C0C0')
                .layoutWeight(1)
                .onClick(() => {
                  this.toggleLocal();
                })
              Button('停止')
                .height(34)
                .backgroundColor('#F2F2F2')
                .fontColor(this.localReady ? '#222222' : '#AAAAAA')
                .layoutWeight(1)
                .onClick(() => {
                  this.stopLocal();
                })
            }
            .width('100%')

            Text(this.localStatus)
              .fontSize(11)
              .fontColor('#EC4141')
              .width('100%')

            List({ space: 0 }) {
              ForEach(this.localTracks, (track: LocalTrack, index: number) => {
                ListItem() {
                  Row() {
                    Text('' + (index + 1))
                      .fontSize(12)
                      .fontColor('#999999')
                      .width(28)
                    Text(track.name)
                      .fontSize(14)
                      .fontColor(index === this.currentIndex ? '#EC4141' : '#222222')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    if (index === this.currentIndex) {
                      Text('▶')
                        .fontSize(12)
                        .fontColor('#EC4141')
                    }
                  }
                  .width('100%')
                  .height(48)
                  .padding({ left: 8, right: 12 })
                  .backgroundColor(index === this.currentIndex ? '#FFF0F0' : '#FFFFFF')
                }
                .onClick(() => {
                  this.playTrack(index);
                })
              }, (track: LocalTrack, index: number) => '' + index)
            }
            .width('100%')
            .layoutWeight(1)
            .divider({ strokeWidth: 1, color: '#F2F2F2' })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 8 })
          .backgroundColor('#FFFFFF')
        }

        if (this.errText.length > 0) {
          Column({ space: 16 }) {
            Text(this.errText)
              .fontSize(14)
              .fontColor('#666666')
              .textAlign(TextAlign.Center)
              .padding({ left: 24, right: 24 })
            Button('重新加载')
              .backgroundColor('#EC4141')
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.refresh();
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#FFFFFF')
        }
      }
      .layoutWeight(1)

      if (!this.isLocal) {
        Row() {
          this.NavButton('←', '后退', this.canBack, () => {
            try {
              this.controller.backward();
            } catch (e) {
              console.error('back failed');
            }
          })
          this.NavButton('→', '前进', this.canForward, () => {
            try {
              this.controller.forward();
            } catch (e) {
              console.error('forward failed');
            }
          })
          this.NavButton('↻', '刷新', true, () => {
            this.refresh();
          })
          this.NavButton('⌂', '首页', true, () => {
            this.goHome();
          })
          this.NavButton('⌕', '搜索', true, () => {
            this.goSearch();
          })
        }
        .width('100%')
        .height(54)
        .backgroundColor('#1A1A1A')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}

