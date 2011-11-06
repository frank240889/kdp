package com.kaltura.vo
{
	import com.kaltura.vo.BaseFlexVo;
	[Bindable]
	public dynamic class KalturaStatsKmcEvent extends BaseFlexVo
	{
		/** 
		* 		* */ 
		public var clientVer : String = null;

		/** 
		* 		* */ 
		public var kmcEventActionPath : String = null;

		/** 
		* 		* */ 
		public var kmcEventType : int = int.MIN_VALUE;

		/** 
		* the client's timestamp of this event
		* */ 
		public var eventTimestamp : Number = Number.NEGATIVE_INFINITY;

		/** 
		* a unique string generated by the client that will represent the client-side session: the primary component will pass it on to other components that sprout from it		* */ 
		public var sessionId : String = null;

		/** 
		* 		* */ 
		public var partnerId : int = int.MIN_VALUE;

		/** 
		* 		* */ 
		public var entryId : String = null;

		/** 
		* 		* */ 
		public var widgetId : String = null;

		/** 
		* 		* */ 
		public var uiconfId : int = int.MIN_VALUE;

		/** 
		* the partner's user id 		* */ 
		public var userId : String = null;

		/** 
		* will be retrieved from the request of the user 		* */ 
		public var userIp : String = null;

		/** 
		* a list of attributes which may be updated on this object 
		* */ 
		public function getUpdateableParamKeys():Array
		{
			var arr : Array;
			arr = new Array();
			arr.push('clientVer');
			arr.push('kmcEventActionPath');
			arr.push('kmcEventType');
			arr.push('eventTimestamp');
			arr.push('sessionId');
			arr.push('partnerId');
			arr.push('entryId');
			arr.push('widgetId');
			arr.push('uiconfId');
			arr.push('userId');
			return arr;
		}

		/** 
		* a list of attributes which may only be inserted when initializing this object 
		* */ 
		public function getInsertableParamKeys():Array
		{
			var arr : Array;
			arr = new Array();
			return arr;
		}

	}
}
