/*
This file is part of the Kaltura Collaborative Media Suite which allows users
to do with audio, video, and animation what Wiki platfroms allow them to do with
text.

Copyright (C) 2006-2008  Kaltura Inc.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

@ignore
*/
package com.kaltura.components.players.events
{
	import flash.events.Event;

	public class PlayerBufferEvent extends Event
	{
		public static const PLAYER_BUFFER_STATUS:String = "playerBufferStatus";

		public var playheadTime:Number = 0;
		public var bufferingStatus:int;

		public function PlayerBufferEvent(type:String, buffering_status:int, playhead_time:Number):void
		{
			super(type, true, false);
			playheadTime = playhead_time;
			bufferingStatus = buffering_status;
		}

		override public function clone():Event
		{
			return new PlayerBufferEvent (type, bufferingStatus, playheadTime);
		}
	}
}