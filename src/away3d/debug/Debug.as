package away3d.debug
{
	import com.assukar.airong.utils.Utils;
	
	/** Class for emmiting debuging messages, warnings and errors */
	public class Debug
	{
		public static var active:Boolean = false;
		public static var warningsAsErrors:Boolean = false;
		
		public static function clear():void
		{
		}
		
		public static function delimiter():void
		{
		}
		
		public static function trace(message:Object):void
		{
			if (active)
				Utils.log(message);
		}
		
		public static function warning(message:Object):void
		{
			if (warningsAsErrors) {
				error(message);
				return;
			}
			Utils.log("WARNING: " + message);
		}
		
		public static function error(message:Object):void
		{
			Utils.log("ERROR: " + message);
			throw new Error(message);
		}
	}
}
