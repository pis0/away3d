package away3d.loaders.parsers.particleSubParsers.values.oneD
{
	import away3d.loaders.parsers.particleSubParsers.AllIdentifiers;
	import away3d.loaders.parsers.particleSubParsers.values.ValueSubParserBase;
	import away3d.loaders.parsers.particleSubParsers.values.setters.oneD.LuaExtractSetter;
	
	public class LuaExtractSubParser extends ValueSubParserBase
	{
		public function LuaExtractSubParser(propName:String)
		{
			super(propName, VARIABLE_VALUE);
		}
		
		override public function parseAsync(data:*, frameLimit:Number = 30):void
		{
			super.parseAsync(data, frameLimit);
			_setter = new LuaExtractSetter(_propName, _data.value);
		}
		
		public static function get identifier():*
		{
			return AllIdentifiers.LuaExtractSubParser;
		}
	}
}
