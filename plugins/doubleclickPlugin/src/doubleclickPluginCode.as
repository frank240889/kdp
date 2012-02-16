package
{
	import com.google.ads.instream.api.Ad;
	import com.google.ads.instream.api.AdBreakTypes;
	import com.google.ads.instream.api.AdBreaksInitializedEvent;
	import com.google.ads.instream.api.AdError;
	import com.google.ads.instream.api.AdErrorEvent;
	import com.google.ads.instream.api.AdEvent;
	import com.google.ads.instream.api.AdLoadedEvent;
	import com.google.ads.instream.api.AdSizeChangedEvent;
	import com.google.ads.instream.api.AdTypes;
	import com.google.ads.instream.api.AdsListLoadedEvent;
	import com.google.ads.instream.api.AdsListManager;
	import com.google.ads.instream.api.AdsLoadedEvent;
	import com.google.ads.instream.api.AdsLoader;
	import com.google.ads.instream.api.AdsManager;
	import com.google.ads.instream.api.AdsManagerTypes;
	import com.google.ads.instream.api.AdsRequest;
	import com.google.ads.instream.api.AdsRequestType;
	import com.google.ads.instream.api.CompanionAd;
	import com.google.ads.instream.api.CompanionAdEnvironments;
	import com.google.ads.instream.api.FlashAd;
	import com.google.ads.instream.api.FlashAdCustomEvent;
	import com.google.ads.instream.api.FlashAdsManager;
	import com.google.ads.instream.api.FlashAsset;
	import com.google.ads.instream.api.HtmlCompanionAd;
	import com.google.ads.instream.api.VastVideoAd;
	import com.google.ads.instream.api.VideoAd;
	import com.google.ads.instream.api.VideoAdsManager;
	import com.kaltura.kdpfl.model.type.AdsNotificationTypes;
	import com.kaltura.kdpfl.model.type.NotificationType;
	import com.kaltura.kdpfl.plugin.IMidrollSequencePlugin;
	import com.kaltura.kdpfl.plugin.IPlugin;
	import com.kaltura.kdpfl.plugin.IPluginFactory;
	import com.kaltura.kdpfl.plugin.ISequencePlugin;
	import com.kaltura.kdpfl.plugin.component.DoubleclickMediator;
	import com.kaltura.kdpfl.view.media.KMediaPlayer;
	import com.yahoo.astra.fl.controls.AbstractButtonRow;
	
	import fl.core.UIComponent;
	
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.SecurityErrorEvent;
	import flash.events.TimerEvent;
	import flash.external.ExternalInterface;
	import flash.geom.Point;
	import flash.media.SoundTransform;
	import flash.media.Video;
	import flash.net.NetStream;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	import flash.net.URLRequestMethod;
	import flash.net.URLVariables;
	import flash.utils.Timer;
	
	import org.puremvc.as3.interfaces.IFacade;
	
	public dynamic class doubleclickPluginCode extends UIComponent implements IPlugin, ISequencePlugin
	{
		
		private static const WRITE_INTO_COMPANION_DIV:String = "writeIntoCompanionDiv";
		public var debugMode:Boolean;
		public var adSlotWidth:Number;
		public var adSlotHeight:Number;
		//this is populated by the config which overrides the adOppTagUrl
		public var adTagUrl : String;
		//this is populated by the KMC
		public var adOppTagUrl:String;
		
		public var adType : String = AdsRequestType.VIDEO;
		public var container:DisplayObjectContainer;
		public var postSequence:int;
		public var preSequence:int;
		public var midSequence:int; 
		//storage of all overlay ads managers		
		private var _overlayAdsManager:Array;
		//storage of all video ads managers 
		private var _videoAdsManager:Array;
		private var _adLoaders:Array;
		private var _adsListManager:AdsListManager;
		private var _playHead:Object	= new Object();
		// For ads list a single ad break might contain >1 ads manager. In such case
		// we need to play all ads managers for an ad break.
		private var _pendingAdsManagers:Array/*AdsManager*/ = [];
		
		private var kMediaPlayer:KMediaPlayer;
		private var playHeadTimer:Timer	=	new Timer(1000);
		private var _channels:Array;
		private var _useGUT:Boolean;
		private var _flashVars:Object;
		private var _adNetStream:NetStream;
		private var _adTimer:Timer	= new Timer(1000);
		//used to adjust netstream volumes
		private var _sndTransform:SoundTransform	= new SoundTransform();
		//list of active netstreams
		private var _netStreams:Array;
		public var trackCuePoints:String="true";
		public var cmsId:String;
		private var _myWidth:Number;
		public function set channels(val:String):void{
			_channels			= val.split(","); 
		}
		public function get channels():String{
			return String(_channels);
		}
		public var contentId : String;
		public var publisherId : String;
		public var disableCompanionAds : String = "false";
		
		
		public function doubleclickPluginCode()
		{
			super();
		}
		
		private var _facade:IFacade;
		public var video:Video;
		
		
		private var _doubleclickMediator:DoubleclickMediator; 
		
		public function initializePlugin(facade:IFacade):void {
			_facade	= facade;	
			_doubleclickMediator	= new DoubleclickMediator(this);
			_doubleclickMediator.eventDispatcher.addEventListener(NotificationType.CHANGE_MEDIA, onInit);
			_doubleclickMediator.eventDispatcher.addEventListener(DoubleclickMediator.INIT_PREROLL, onPreRoll);
			_doubleclickMediator.eventDispatcher.addEventListener(DoubleclickMediator.INIT_POSTROLL, onPostRoll);
			_doubleclickMediator.eventDispatcher.addEventListener(DoubleclickMediator.INIT_MIDROLL, onMidRoll);
			_doubleclickMediator.eventDispatcher.addEventListener(NotificationType.VOLUME_CHANGED, onVolumeChange);
			//			_doubleclickMediator.eventDispatcher.addEventListener(NotificationType.PLAYBACK_COMPLETE, onPlaybackComplete);
			_doubleclickMediator.preSequence = preSequence;
			_doubleclickMediator.postSequence = postSequence;
			facade.registerMediator(_doubleclickMediator);
			
		}
		
		private function onVolumeChange(e:Event):void{
			_sndTransform.volume			= this._doubleclickMediator.getVolume();
			changeVolume();
		}
		
		private function changeVolume():void{
			for each (var ns:NetStream in _netStreams){
				ns.soundTransform		= _sndTransform;
			}
		}
		
		
		
		private function onAdLoaded(event:AdLoadedEvent):void {
			//retain reference to each netstream
			_adNetStream			= event.netStream;
			_adTimer.addEventListener(TimerEvent.TIMER,onAdTimer);
			_adTimer.start();
			
			if(event.netStream != null){
				_netStreams.push(event.netStream);
				changeVolume();
			}			
		}
		private function onAdTimer(e:TimerEvent):void{
			_facade.sendNotification("adUpdatePlayhead",_adNetStream.time);
		}
		
		private function onPreRoll(e:Event):void{
			onLoadAd();
		}
		private function onPostRoll(e:Event):void{
			//if using adRule play that instead of loading ad
			if(_adsListManager && _adsListManager.hasAdBreak(AdBreakTypes.POSTROLL))
				_adsListManager.initAdBreak(AdBreakTypes.POSTROLL);
			else if(adType !=  AdsRequestType.TEXT_OVERLAY &&
				adType != AdsRequestType.TEXT &&
				adType != AdsRequestType.TEXT_OR_GRAPHICAL &&
				adType != AdsRequestType.TEXT_FULL_SLOT)//some ads dont' qualify as postroll
				onLoadAd();
		}
		private function onMidRoll(e:Event):void{
			onLoadAd();
		}
		
		
		//sending preSequenceNotificationStartName notification generates 2 events for some reason.  
		//this flag is to prevent ads from stacking up. 
		private var _adIsLoaded:Boolean 	= false;
		private function onLoadAd(event:Event = null):void {
			if(!_adIsLoaded){
				if(video)
					video.visible	= true;
				_adIsLoaded	= true;
				loadAd();
			}
		}
		
		
		private var adsLoader:AdsLoader;
		private var adsRequest:AdsRequest;
		
		//occurs after each change media event
		private function onInit(e:Event):void{
			_netStreams		= new Array();
			
			if(!video){//initial load
				_overlayAdsManager		= new Array();
				_videoAdsManager		= new Array();
				_adLoaders				= new Array();
				video 					= new Video();
				video.width				= this.width;
				video.height			= this.height;
				addChild(video);
			}
			playHeadTimer.reset();
			playHeadTimer.stop();
			
			unloadAds();
		}
		
		private function unloadAds():void{
			//clear overlay ads
			while(_overlayAdsManager.length > 0){
				if(this.contains(_overlayAdsManager[0]))
					removeChild(_overlayAdsManager[0]);
				
				_overlayAdsManager[0]	= null;
				
				_overlayAdsManager.shift();
			}
			
			//clear video ads
			while(_videoAdsManager.length > 0){
				_videoAdsManager[0].unload();
				_videoAdsManager[0]	= null;
				_videoAdsManager.shift();
			}
			
			//clear ad loaders
			/*
			for each (var loader:AdsLoader in _adLoaders){
			loader 	= null;
			}*/
			while(_adLoaders.length > 0){
				_adLoaders[0]	= null;
				_adLoaders.shift();
			}
		}
		
		override public function set width(value:Number):void
		{
			_myWidth = value;
			super.width = value;
			updateSizes();
		}	
		
		/**
		 * Function to start playing the plugin content - each plugin implements this differently
		 * 
		 */		
		public function start () : void{
			_doubleclickMediator.forceStart();
		}
		
		/**
		 * Creates the AdsLoader object if its not present
		 * and request ads using the AdsLoader object.
		 */
		private function loadAd():void {
			log("DOUBLECLICK#loadAd");
			//TODO:hack remove later
			adsLoader = new AdsLoader();
			_adLoaders.push(adsLoader);
			adsLoader.addEventListener(AdsLoadedEvent.ADS_LOADED, onAdsLoaded);
			adsLoader.addEventListener(AdsListLoadedEvent.LOADED, onAdsListLoaded);
			adsLoader.addEventListener(AdErrorEvent.AD_ERROR, onAdError);
			
			adsLoader.requestAds(createAdsRequest());
		}
		
		
		private function onAdsListLoaded(adsListEvent:AdsListLoadedEvent):void{
			log("DOUBLECLICK#onAdsListLoaded");
			playHeadTimer.addEventListener(TimerEvent.TIMER, onPlayHeadTimer);
			kMediaPlayer			= (_facade["bindObject"]["video"] as KMediaPlayer);
			playHeadTimer.start();
			checkForAd(adsListEvent);
		}
		
		private function onPlayHeadTimer(e:TimerEvent):void{
			//trace(kMediaPlayer.player.currentTime);
			_playHead["time"]		= kMediaPlayer.player.currentTime;
		}
		
		private function checkForAd(adsListEvent:AdsListLoadedEvent = null):void{
			log("DOUBLECLICK#checkForAd-begin1");
			//e.getAdsListManager();
			//var adsListManager:AdsListManager;
			_playHead					= {time:kMediaPlayer.player.currentTime};
			_adsListManager 			= adsListEvent.getAdsListManager(_playHead);
			
			// This event is raised when either a mid-roll ad list is automatically
			// triggered based on the content playhead or manually with the 
			// initAdBreak when the ad list is a pre-roll or post-roll ad list
			_adsListManager.addEventListener(AdBreaksInitializedEvent.INITIALIZED, adBreaksInitializedEventHandler);
			// Raised when an error or empty ad list is returned
			_adsListManager.addEventListener(AdErrorEvent.AD_ERROR, adErrorHandler);
			
			// Initialize preroll ad break if it's present.
			if(_adsListManager.hasAdBreak(AdBreakTypes.PREROLL)){
				_adsListManager.initAdBreak(AdBreakTypes.PREROLL);
			}
			
			log("DOUBLECLICK#checkForAd-end");
		}
		
		//flag indicating if adbreak is from ad list or cuepoint. 
		private var _isAdRuleMidBreak:Boolean	= false;
		
		private function adBreaksInitializedEventHandler(event:AdBreaksInitializedEvent):void{
			log("DOUBLECLICK#adBreaksInitializedEventHandler2	-	TOTAL ADS:xxxxxx");
			if(_playHead["time"] < kMediaPlayer.player.duration)
				_isAdRuleMidBreak		= true;
			
			_doubleclickMediator.pauseDisablePlayer();
			log("DOUBLECLICK#adBreaksInitializedEventHandler2	-	TOTAL ADS:"+event.adBreaks[0].adsManagers.length);
			var adBreaks:Array = event.adBreaks;
			// If there's more than 1 ad break, means video player's playhead moved
			// ahead over more than 1 ad break. This would be a common case when user
			// seeks forward. It's up to publisher to choose to play 1st, last or all
			// ad breaks. We pick the first ad break.
			// In this example, I load the first ad break only.
			if (!isArrayEmpty(adBreaks)) {
				_pendingAdsManagers = _pendingAdsManagers.concat(
					event.adBreaks[0].adsManagers);
				playNextAdBreakAdsManager();
			}
		}
		
		/**
		 * @return <code>true</code> if the array is empty or null.
		 */
		public static function isArrayEmpty(array:Array):Boolean {
			return array == null || array.length == 0;
		}
		
		
		private function playNextAdBreakAdsManager():void {
			log("DOUBLECLICK#playNextAdBreakAdsManager");
			
			var nextAdsManager:AdsManager;
			
			// There can be more than 1 ads manager to play ads back to back. For
			// now video and overlays can't be mixed with one exception, overlay
			// can be the last ads manager in a list of video ads managers.
			if (!isArrayEmpty(_pendingAdsManagers)) {
				// Pick the first ads manager to play.
				nextAdsManager = _pendingAdsManagers.shift();
				
				// If we hit a non-linear, play the content, then the ad.
				if( (nextAdsManager.type == AdsManagerTypes.FLASH) && 
					( nextAdsManager.ads != null ) && 
					( nextAdsManager.ads.length > 0 ) ) {
					var ad:Ad = nextAdsManager.ads[0];
					
					if(!ad.linear) {
						onVideoAdComplete();
					}
				}
				constructAdManager(nextAdsManager);
				
			} else {
				log("No ad breaks left, if this is the end after the post-roll and " +
					"content, you may want to bring up another window.");
			}
			
		}
		
		
		/**
		 *  
		 * Override the height property, in order to knwo when to call callResize
		 * @param value the new height
		 * @return 
		 * 
		 */		
		private var _myHeight:Number;
		override public function set height(value:Number):void
		{
			_myHeight = value;
			super.height = value;
			updateSizes();
		}	
		
		private function updateSizes():void
		{
			callLater(callResize);
		}
		
		/**
		 *  
		 * Update the doubleclick player that the size of the stage changed (and it needs to fit)
		 * @param 
		 * @return 
		 * 
		 */		
		private function callResize():void
		{
			
			if(parent && video)
			{ 
				video.width  = _myWidth;
				video.height = _myHeight;
			}
			
			//resize adsManager if available
			if(_videoAdsManager){
				for each(var adsMan:AdsManager in _videoAdsManager){
					adsMan.adSlotHeight			= this.height;
					adsMan.adSlotWidth			= this.width;			
				}
			}
			
		}
		
		private var adsManagerx:AdsManager;
		private var _adAvailable:Boolean	= false;
		
		private function unloadAd(adsManager:AdsManager):void {
			try {
				if (adsManager) {
					log("[DOUBLECLICK] - unload ad");
					adsManager.unload();
					removeListeners(adsManager);
					removeAdsManagerListeners(adsManager);
				}
			} catch (e:Error) {
				log("doubleclickError occured during unload : " + e.message + e.getStackTrace());
			}
		}
		
		private function clearVideo():void {
			if (video){video.clear();}
		}
		
		private function removeListeners(adsManager:AdsManager):void {
			//adsManager.removeEventListener(AdLoadedEvent.LOADED, onAdLoaded);
			if (adsManager.type == AdsManagerTypes.VIDEO) {
				var videoAdsManager:VideoAdsManager = adsManager as VideoAdsManager;
				videoAdsManager.removeEventListener(AdEvent.STOPPED, onVideoAdStopped);
				//videoAdsManager.removeEventListener(AdEvent.STARTED, onAdStarted);
				videoAdsManager.removeEventListener(AdEvent.PAUSED, onVideoAdPaused);
				videoAdsManager.removeEventListener(AdEvent.COMPLETE, onVideoAdComplete);
				videoAdsManager.removeEventListener(AdEvent.MIDPOINT,onVideoAdMidpoint);
				videoAdsManager.removeEventListener(AdEvent.FIRST_QUARTILE, onVideoAdFirstQuartile);
				videoAdsManager.removeEventListener(AdEvent.THIRD_QUARTILE,onVideoAdThirdQuartile);
				videoAdsManager.removeEventListener(AdEvent.RESTARTED, onVideoAdRestarted);
				videoAdsManager.removeEventListener(AdEvent.VOLUME_MUTED, onVideoAdVolumeMuted);
			} else if (adsManager.type == AdsManagerTypes.FLASH) {
				var flashAdsManager:FlashAdsManager = adsManager as FlashAdsManager;
				flashAdsManager.removeEventListener(AdSizeChangedEvent.SIZE_CHANGED, onFlashAdSizeChanged);
				flashAdsManager.removeEventListener(FlashAdCustomEvent.CUSTOM_EVENT, onFlashAdCustomEvent);
			}
		}
		
		private function removeAdsManagerListeners(adsManager:AdsManager):void {
			adsManager.removeEventListener(AdErrorEvent.AD_ERROR, onAdError);
			adsManager.removeEventListener(AdEvent.CONTENT_PAUSE_REQUESTED, onContentPauseRequested);
			adsManager.removeEventListener(AdEvent.CONTENT_RESUME_REQUESTED, onContentResumeRequested);
			adsManager.removeEventListener(AdEvent.CLICK, onAdClicked);
			adsManager.removeEventListener(AdEvent.STARTED, onAdStarted);
		}
		
		public function loadNonLinearAd():void{
			onLoadAd();
		}
		
		/**
		 * This method is used to create the AdsRequest object which is used by the
		 * AdsLoader to request ads.
		 */
		private function createAdsRequest():AdsRequest {
			var request:AdsRequest	= new AdsRequest();
			
			request.adSlotHeight			= _facade["bindObject"]["video"].height;
			
			request.adSlotWidth				= _facade["bindObject"]["video"].width;
			
			request.adSlotHorizontalAlignment	= _facade["bindObject"]["video"].width;
			request.adSlotVerticalAlignment		= _facade["bindObject"]["video"].height;
			
			//use adTagUrl property if value exist else use ad break opporunity tag url.
			if(hasValue(adTagUrl))
				request.adTagUrl			= adTagUrl;
			else if(adOppTagUrl != ""){
				request.adTagUrl			= adOppTagUrl;
				adOppTagUrl					= "";
			}
			
			
			if(hasValue(adType))
				request.adType				= AdsRequestType[adType.toUpperCase()];
			
			if(_channels.length > 0)
				request.channels			= _channels;
			else
				request.channels			= [];
			
			if(hasValue(contentId))
				request.contentId = (contentId == "null")?null:contentId;
			
			if(hasValue(publisherId))
				request.publisherId =	(publisherId == "null")?null:publisherId;
			
			if(hasValue(disableCompanionAds))
				request.disableCompanionAds	= (disableCompanionAds.toUpperCase() == "TRUE")?true:false;
			
			if(hasValue(cmsId))
				request.cmsId	= 			cmsId;
			
			// Checks the companion type from flashVars to decides whether to use GUT
			// or getCompanionAds() to load companions.
			
			_flashVars = _facade.retrieveProxy("configProxy")["vo"]["flashvars"];
			_useGUT = _flashVars != null && _flashVars.useGUT == "false" ? false : true;
			if (!_useGUT) {
				request.disableCompanionAds = true;
			}
			
			log("[DOUBLECLICK] sent REQUEST::::::: adSlotHeight: 			"+request.adSlotHeight);
			log("[DOUBLECLICK] sent REQUEST::::::: adSlotWidth: 			"+request.adSlotWidth);
			log("[DOUBLECLICK] sent REQUEST::::::: adTagUrl: 				"+request.adTagUrl);
			log("[DOUBLECLICK] sent REQUEST::::::: adType:		 			"+request.adType);
			log("[DOUBLECLICK] sent REQUEST::::::: channels:				"+request.channels);
			log("[DOUBLECLICK] sent REQUEST::::::: contentId:				"+request.contentId);
			log("[DOUBLECLICK] sent REQUEST::::::: publisherId:				"+request.publisherId);
			log("[DOUBLECLICK] sent REQUEST::::::: disableCompanionAds:		"+request.disableCompanionAds);
			log("[DOUBLECLICK] sent REQUEST::::::: cmsId:					"+request.cmsId);
			
			return request;
		}
		
		/**
		 * This method is invoked when the adsLoader has completed loading an ad
		 * using the adsRequest object provided.
		 */
		private function loadFlashAd(manager:AdsManager):void{
			var flashAdContainer:Sprite = new Sprite();
			addChild(flashAdContainer);
			var videoPlaceHolder:DisplayObject = this;
			var point:Point = videoPlaceHolder.localToGlobal(new Point(videoPlaceHolder.x,videoPlaceHolder.y));
			(manager as FlashAdsManager).decoratedAd	= true;
			(manager as FlashAdsManager).x = point.x;
			(manager as FlashAdsManager).y = point.y;
			(manager as FlashAdsManager).load();
			(manager as FlashAdsManager).play(flashAdContainer);	
		}
		
		private function onAdsLoaded(adLoadedEvent:AdsLoadedEvent):void{
			constructAdManager(adLoadedEvent.adsManager);
		}
		
		private function constructAdManager(adsManager:AdsManager):void {
			//TODO:hack remove later
			this.visible	= true;
			_facade.sendNotification(AdsNotificationTypes.AD_START);
			adsManager.addEventListener(AdErrorEvent.AD_ERROR, onAdError);
			adsManager.addEventListener(AdEvent.CONTENT_PAUSE_REQUESTED, onContentPauseRequested);
			adsManager.addEventListener(AdEvent.CONTENT_RESUME_REQUESTED, onContentResumeRequested);
			adsManager.addEventListener(AdLoadedEvent.LOADED, onAdLoaded);
			adsManager.addEventListener(AdEvent.STARTED, onAdStarted);
			displayAdsInformation(adsManager);
			
			if (adsManager.type == AdsManagerTypes.FLASH) {
				var flashAdsManager:FlashAdsManager = adsManager as FlashAdsManager;
				flashAdsManager.addEventListener(AdSizeChangedEvent.SIZE_CHANGED,onFlashAdSizeChanged);
				flashAdsManager.addEventListener(FlashAdCustomEvent.CUSTOM_EVENT,onFlashAdCustomEvent);
				
				loadFlashAd(flashAdsManager);
				
				//retain overlay ads manager
				_overlayAdsManager.push(flashAdsManager);
				
				//call ad complete for flash ads to continue sequence.
				onVideoAdComplete();
			} else if (adsManager.type == AdsManagerTypes.VIDEO) {
				//addChild(video);
				var videoAdsManager:VideoAdsManager = adsManager as VideoAdsManager;
				videoAdsManager.addEventListener(AdEvent.STARTED,onAdStarted);
				videoAdsManager.addEventListener(AdEvent.STOPPED,onVideoAdStopped);
				videoAdsManager.addEventListener(AdEvent.PAUSED, onVideoAdPaused);
				videoAdsManager.addEventListener(AdEvent.COMPLETE, onVideoAdComplete);
				videoAdsManager.addEventListener(AdEvent.MIDPOINT, onVideoAdMidpoint);
				videoAdsManager.addEventListener(AdEvent.FIRST_QUARTILE, onVideoAdFirstQuartile);
				videoAdsManager.addEventListener(AdEvent.THIRD_QUARTILE, onVideoAdThirdQuartile);
				videoAdsManager.addEventListener(AdEvent.RESTARTED, onVideoAdRestarted);
				videoAdsManager.addEventListener(AdEvent.VOLUME_MUTED, onVideoAdVolumeMuted);
				
				videoAdsManager.clickTrackingElement = this;	
				videoAdsManager.load(video);
				videoAdsManager.play(video);
				
				//retain video ads manager
				_videoAdsManager.push(adsManager);
				
				//dispatching adStart notification here because AdEvent.STARTED is fired off multiple times.
				//will follow up with google on this. 
			} 
		}
		
		
		private function onVideoAdComplete(e:AdEvent = null):void{
			log("[DOUBLECLICK] onVideoAdComplete");
			for each(var adManager:AdsManager in _videoAdsManager){
				unloadAd(adManager);
			}
			_facade.sendNotification(AdsNotificationTypes.AD_END);
			//if more videos in pendingAdsManager play next item
			if (!isArrayEmpty(_pendingAdsManagers)) {
				playNextAdBreakAdsManager();
			} else {//else resume content
				_adTimer.stop();
				_adTimer.removeEventListener(TimerEvent.TIMER, onAdTimer);
				
				_adIsLoaded	= false;
				
				clearVideo();
				
				_facade.sendNotification(NotificationType.SEQUENCE_ITEM_PLAY_END);
				_doubleclickMediator.enableControls();
				if(_isAdRuleMidBreak){
					_doubleclickMediator.playEnablePlayer();
					_isAdRuleMidBreak		= false;
				}else{	
					_facade.sendNotification("enableGui", {guiEnabled: true, enableType: "full"});
				}
				//TODO:hack remove later
				this.visible	= false;
				unloadAds();
			}
			
		}
		
		/**
		 * This method is used to log information regarding the AdsManager and
		 * the Ad objects.
		 *
		 * Publishers will usually not need to do this unless they are interested
		 * in logging or otherwise processing data about the ads.
		 */
		private function displayAdsInformation(adsManager:Object):void {
			var ads:Array = adsManager.ads;
			if (ads) {
				for each (var ad:Ad in ads) {
					try {
						// APIs defined on Ad
						// Check the companion type from flashVars to decide whether to use
						// GUT or getCompanionAds() to load companions.
						if (!_useGUT) {
							renderHtmlCompanionAd(
								ad.getCompanionAds(CompanionAdEnvironments.HTML, 300, 250),"300x250");
							renderHtmlCompanionAd(
								ad.getCompanionAds(CompanionAdEnvironments.HTML, 728, 90),"728x90");
						}
						if (ad.type == AdTypes.VAST) {
							var vastAd:VastVideoAd = ad as VastVideoAd;
							log("description: " + vastAd.description);
							log("adSystem: " + vastAd.adSystem);
							log("customClicks: " + vastAd.customClicks);
						} else if (ad.type == AdTypes.VIDEO) {
							// APIs defined on all video ads
							var videoAd:VideoAd = ad as VideoAd;
							log("author: " + videoAd.author);
							log("title: " + videoAd.title);
							log("ISCI: " + videoAd.ISCI);
							log("deliveryType: " + videoAd.deliveryType);
							log("mediaUrl: " + videoAd.mediaUrl);
							// getCompanionAdUrl will throw error for VAST ads.
							log("getCompanionAdUrl: " + ad.getCompanionAdUrl("flash"));
						} else if (ad.type == AdTypes.FLASH) {
							// API defined on FlashAd
							var flashAd:FlashAd = ad as FlashAd;
							if (flashAd.asset != null) {
								log("asset: " + flashAd.asset);
								log("asset x: " + flashAd.asset.x);
								log("asset y: " + flashAd.asset.y);
								log("asset height: " + flashAd.asset.height);
								log("asset width: " + flashAd.asset.width);
							} else {
								log("Error: flashAsset is null.");
							}
						}
						
					} catch (error:Error) {
						log("[DOUBLECLICK] Error type:" + error + " message:" + error.message);
					}
				}
			}
		}
		
		
		private function onAdStarted(event:AdEvent):void {
			log("[DOUBLECLICK] sent!!! : db adsManager sent "+event.type);
		}
		
		private function onAdClicked(event:AdEvent):void {
			log("[DOUBLECLICK] sent : db adsManager sent "+event.type);
		}
		
		private function onFlashAdSizeChanged(event:AdSizeChangedEvent):void {
			log("[DOUBLECLICK] sent SIZE CHANGE:  "+event.type +" "+ event.adType+" "+ event.width+" "+ event.height+" "+ event.state+" "+ event.ad);
			var flashAd:FlashAd = event.ad as FlashAd;
			if (flashAd.asset != null) {
				//TODO::: will this not resize overlay ads in fullscreen if commented out? - Nu
				//					loadFlashAd(adsManager);
				log("[DOUBLECLICK] sent type: " + flashAd.asset.type);
				log("[DOUBLECLICK] sent asset: " + flashAd.asset);
				log("[DOUBLECLICK] sent asset x: " + flashAd.asset.x);
				log("[DOUBLECLICK] sent asset y: " + flashAd.asset.y);
				log("[DOUBLECLICK] sent asset height: " + flashAd.asset.height);
				log("[DOUBLECLICK] sent asset width: " + flashAd.asset.width);
				
			} else {
				log("Error: flashAsset is null.");
			}
		}
		
		private function onFlashAdCustomEvent(event:FlashAdCustomEvent):void {
			log("[DOUBLECLICK] sent FLASH AD CUSTOM EVENT:"+event.type);
		}
		private function onVideoAdStopped(event:AdEvent):void {
			log("[DOUBLECLICK] sent : "+event.type);
		}
		
		private function onVideoAdPaused(event:AdEvent):void {
			log("[DOUBLECLICK] sent : "+event.type);
		}
		
		private function onVideoAdMidpoint(event:AdEvent):void {
			log("[DOUBLECLICK] sent : "+event.type);
		}
		
		private function onVideoAdFirstQuartile(event:AdEvent):void {
			log("[DOUBLECLICK] sent : "+event.type);
		}
		
		private function onVideoAdThirdQuartile(event:AdEvent):void {
			log("[DOUBLECLICK] sent : "+event.type);
		}
		
		private function onVideoAdClicked(event:AdEvent):void {
			log("[DOUBLECLICK] sent : "+event.type);
		}
		
		private function onVideoAdRestarted(event:AdEvent):void {
			log("[DOUBLECLICK] sent : "+event.type);
		}
		
		private function onVideoAdVolumeMuted(event:AdEvent):void {
			log("[DOUBLECLICK] sent : "+event.type);
		}
		
		private function renderHtmlCompanionAd(companionArray:Array,size:String):void {
			if (companionArray.length > 0) {
				log("[DOUBLECLICK] There are " + companionArray.length + " companions for this ad.");
				var companion:CompanionAd = companionArray[0] as CompanionAd;
				if (companion.environment == CompanionAdEnvironments.HTML) {
					log("[DOUBLECLICK] companion " + size + " environment: " + companion.environment);
					var htmlCompanion:HtmlCompanionAd = companion as HtmlCompanionAd;
					if(ExternalInterface.available) {
						ExternalInterface.call(WRITE_INTO_COMPANION_DIV,htmlCompanion.content,size);
					}
				}
			}
		}
		
		/**
		 * This method is invoked when an interactive flash ad raises the
		 * contentPauseRequested event.
		 *
		 * We recommend that publishers pause their video content when this method
		 * is invoked. This is usually because the ad will play within the video
		 * player itself or cover the video player so that the publisher content
		 * would not be easily visible.
		 */
		private function onContentPauseRequested(event:AdEvent):void {
			
		}
		
		
		/**
		 * This method is invoked when an interactive flash ad raises the
		 * contentResumeRequested event.
		 *
		 * We recommend that publishers resume their video content when this method
		 * is invoked. This is because the ad has completed playing and the
		 * publisher content should be resumed from the time it was paused.
		 */
		private function onContentResumeRequested(event:AdEvent = null):void {
			_facade.sendNotification(NotificationType.SEQUENCE_ITEM_PLAY_END);
		}
		
		
		
		
		
		
		private function adErrorHandler(adErrorEvent:AdErrorEvent):void{
			log("[DOUBLECLICK]#adErrorHandler");
			var adError:AdError = adErrorEvent.error;
			
			log("message: " + adError.errorMessage);
			log("errorType: " + adError.errorType);
			log("innerError: " + adError.innerError); 
			log("errorCode: " + adError.errorCode);
			log("=== Ad Error === ");
			
			onVideoAdComplete();
		}
		
		private function hasValue(val:String):Boolean{
			return (val != "" && val != "undefined" && val != null)?true:false;
		}
		
		/**
		 *Function returns whether the plugin in question has a sub-sequence 
		 * @return The function returns true if the plugin has a sub-sequence, false otherwise.
		 * 
		 */		
		public function hasSubSequence() : Boolean{return false;}
		
		/**
		 * Function returns the length of the sub-sequence length of the plugin 
		 * @return The function returns an integer signifying the length of the sub-sequence;
		 * 			If the plugin has no sub-sequence, the return value is 0.
		 */		
		public function subSequenceLength () : int{return 0;}
		
		/**
		 * Returns whether the Sequence Plugin plays within the KDP or loads its own media over it. 
		 * @return The function returns <code>true</code> if the plugin media plays within the KDP
		 *  and <code>false</code> otherwise.
		 * 
		 */		
		public function hasMediaElement () : Boolean{log("[DOUBLECLICK] plugin: hasMediaElement()");return false;}
		
		/**
		 * Function for retrieving the entry id of the plugin media
		 * @return The function returns the entry id of the plugin media. If the plugin does not play
		 * 			a kaltura-based entry, the return value is the URL of the media of the plugin.
		 */		
		public function get entryId () : String{log("[DOUBLECLICK] plugin: entryId()");return "0_kjvoet76";}
		
		/**
		 * Function for retrieving the source type of the plugin media (url or entryId) 
		 * @return If the plugin plays a Kaltura-Based entry the function returns <code>entryId</script>.
		 * Otherwise the return value is <code>url</script>
		 * 
		 */		
		public function get sourceType () : String{log("[DOUBLECLICK] plugin: sourceType()");return "entryId";}
		/**
		 * Function to retrieve the MediaElement the plugin will play in the KDP. 
		 * @return returns the MediaElement that the plugin will play in the KDP. 
		 * 
		 */		
		public function get mediaElement () : Object{log("[DOUBLECLICK] plugin: mediaElement()");return new Object()}
		
		/**
		 * Function for determining where to place the ad in the pre sequence; 
		 * @return The function returns the index of the plugin in the pre sequence; 
		 * 			if the plugin should not appear in the pre-sequence, return value is -1.
		 */		
		public function get preIndex () : Number{log("[DOUBLECLICK] plugin: preIndex()");return Number(preSequence);}
		
		/**
		 *Function for determining where to place the plugin in the post-sequence. 
		 * @return The function returns the index of the plugin in the post-sequence;
		 * 			if the plugin should not appear in the post-sequence, return value is -1.
		 */		
		public function get postIndex () : Number{log("[DOUBLECLICK] plugin: postIndex()");return Number(postSequence);}
		
		
		
		
		private function onPauseRequested(e:AdEvent):void{
			
		}
		
		private function onResumeRequested(e:AdEvent):void{
			
		}
		
		private function onAdError(e:AdErrorEvent):void{
			log("[DOUBLECLICK] DOUBLE CLICK ON ADS ERROR	"+e);
			//TODO add check if this is a pre/post/mid and context for video/overlay
			onVideoAdComplete();
		}
		
		
		/**
		 * Do nothing.
		 * No implementation required for this interface method on this plugin.
		 * @param styleName
		 * @param setSkinSize
		 */
		public function setSkin(styleName:String, setSkinSize:Boolean = false):void {}
		
		
		private function onSecurityError(e:SecurityErrorEvent):void{
			log("[DOUBLECLICK] ERROR: DOUBLECLICK Plugin - error sending beacon : "+e);
		}
		
		private function onIOError(e:IOErrorEvent):void{
			log("[DOUBLECLICK] ERROR: DOUBLECLICK Plugin - error sending beacon : "+e);
		}
		
		private function log(text:String):void{
			if(debugMode){
				trace(text);
			}
		}
	}
}