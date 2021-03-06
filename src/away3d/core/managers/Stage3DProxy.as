package away3d.core.managers
{
	import away3d.arcane;
	import away3d.events.Stage3DEvent;

	import com.assukar.airong.error.AssukarError;
	import com.assukar.airong.utils.Debug;
	import com.assukar.airong.utils.Utils;

	import flash.display.Shape;
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
	import flash.display3D.Context3DClearMask;
	import flash.display3D.Context3DProfile;
	import flash.display3D.Context3DRenderMode;
	import flash.display3D.Program3D;
	import flash.display3D.textures.TextureBase;
	import flash.events.ErrorEvent;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.geom.Rectangle;
	import flash.utils.setTimeout;
    
    use namespace arcane;
    
    [Event(name="enterFrame", type="flash.events.Event")]
    [Event(name="exitFrame", type="flash.events.Event")]
    
    /**
     * Stage3DProxy provides a proxy class to manage a single Stage3D instance as well as handling the creation and
     * attachment of the Context3D (and in turn the back buffer) is uses. Stage3DProxy should never be created directly,
     * but requested through Stage3DManager.
     *
     * @see away3d.core.managers.Stage3DProxy
     *
     * todo: consider moving all creation methods (createVertexBuffer etc) in here, so that disposal can occur here
     * along with the context, instead of scattered throughout the framework
     */ public class Stage3DProxy extends EventDispatcher
    {
        private static var _frameEventDriver:Shape = new Shape();
        
        arcane var _context3D:Context3D;
        arcane var _stage3DIndex:int = -1;
        
        private var _usesSoftwareRendering:Boolean;
        private var _profile:String;
        private var _stage3D:Stage3D;
        private var _activeProgram3D:Program3D;
        private var _stage3DManager:Stage3DManager;
        private var _backBufferWidth:int;
        private var _backBufferHeight:int;
        private var _antiAlias:int;
        private var _enableDepthAndStencil:Boolean;
        private var _backBufferEnableDepthAndStencil:Boolean = true;
        private var _contextRequested:Boolean;
        //private var _activeVertexBuffers : Vector.<VertexBuffer3D> = new Vector.<VertexBuffer3D>(8, true);
        //private var _activeTextures : Vector.<TextureBase> = new Vector.<TextureBase>(8, true);
        private var _renderTarget:TextureBase;
        private var _renderSurfaceSelector:int;
        private var _scissorRect:Rectangle;
        private var _color:uint;
        private var _backBufferDirty:Boolean;
        private var _viewPort:Rectangle;
        private var _enterFrame:Event;
        private var _exitFrame:Event;
        private var _viewportUpdated:Stage3DEvent;
        private var _viewportDirty:Boolean;
        private var _bufferClear:Boolean;
        private var _mouse3DManager:Mouse3DManager;
        private var _touch3DManager:Touch3DManager;
        
        private function notifyViewportUpdated():void
        {
            if (_viewportDirty)
                return;
            
            _viewportDirty = true;
            
            if (!hasEventListener(Stage3DEvent.VIEWPORT_UPDATED))
                return;
            
            //TODO: investigate bug causing coercion error
            //if (!_viewportUpdated)
            _viewportUpdated = new Stage3DEvent(Stage3DEvent.VIEWPORT_UPDATED);
            
            dispatchEvent(_viewportUpdated);
        }
        
        private function notifyEnterFrame():void
        {
            if (!hasEventListener(Event.ENTER_FRAME))
                return;
            
            if (!_enterFrame) _enterFrame = new Event(Event.ENTER_FRAME);
            
            dispatchEvent(_enterFrame);
        }
        
        private function notifyExitFrame():void
        {
            if (!hasEventListener(Event.EXIT_FRAME))
                return;
            
            if (!_exitFrame) _exitFrame = new Event(Event.EXIT_FRAME);
            
            dispatchEvent(_exitFrame);
        }
        
        /**
         * Creates a Stage3DProxy object. This method should not be called directly. Creation of Stage3DProxy objects should
         * be handled by Stage3DManager.
         * @param stage3DIndex The index of the Stage3D to be proxied.
         * @param stage3D The Stage3D to be proxied.
         * @param stage3DManager
         * @param forceSoftware Whether to force software mode even if hardware acceleration is available.
         */
//        public function Stage3DProxy( stage3DIndex:int, stage3D:Stage3D, stage3DManager:Stage3DManager, forceSoftware:Boolean = false, profile:String = "baseline" )
        public function Stage3DProxy( stage3DIndex:int, stage3D:Stage3D, stage3DManager:Stage3DManager, forceSoftware:Boolean = false, profile:String = null )
        {
            _stage3DIndex = stage3DIndex;
            _stage3D = stage3D;
            _stage3D.x = 0;
            _stage3D.y = 0;
            _stage3D.visible = true;
            _stage3DManager = stage3DManager;
            _viewPort = new Rectangle();
            _enableDepthAndStencil = true;
            
            // whatever happens, be sure this has highest priority
            _stage3D.addEventListener(Event.CONTEXT3D_CREATE, onContext3DUpdate, false, int.MAX_VALUE, true);
            requestContext(forceSoftware, profile);
        }
        
        public function get profile():String
        {
            return _profile;
        }
        
        /**
         * Disposes the Stage3DProxy object, freeing the Context3D attached to the Stage3D.
         */
        public function dispose():void
        {
            _stage3DManager.removeStage3DProxy(this);
            _stage3D.removeEventListener(Event.CONTEXT3D_CREATE, onContext3DUpdate);
            freeContext3D();
            _stage3D = null;
            _stage3DManager = null;
            _stage3DIndex = -1;
        }
        
        /**
         * Configures the back buffer associated with the Stage3D object.
         * @param backBufferWidth The width of the backbuffer.
         * @param backBufferHeight The height of the backbuffer.
         * @param antiAlias The amount of anti-aliasing to use.
         * @param enableDepthAndStencil Indicates whether the back buffer contains a depth and stencil buffer.
         */
        public function configureBackBuffer( backBufferWidth:int, backBufferHeight:int, antiAlias:int ):void
        {
            if (backBufferWidth < 50) backBufferWidth = 50;
            if (backBufferHeight < 50) backBufferHeight = 50;
            var oldWidth:uint = _backBufferWidth;
            var oldHeight:uint = _backBufferHeight;
            
            _backBufferWidth = _viewPort.width = backBufferWidth;
            _backBufferHeight = _viewPort.height = backBufferHeight;
            
            if (oldWidth != _backBufferWidth || oldHeight != _backBufferHeight) notifyViewportUpdated();
            
            _antiAlias = antiAlias;
            
            if (_context3D) _context3D.configureBackBuffer(backBufferWidth, backBufferHeight, antiAlias, _backBufferEnableDepthAndStencil);
        }
        
        /*
         * Indicates whether the depth and stencil buffer is used
         */
        public function get enableDepthAndStencil():Boolean
        {
            return _enableDepthAndStencil;
        }
        
        public function set enableDepthAndStencil( enableDepthAndStencil:Boolean ):void
        {
            _enableDepthAndStencil = enableDepthAndStencil;
            _backBufferDirty = true;
        }
        
        public function get renderTarget():TextureBase
        {
            return _renderTarget;
        }
        
        public function get renderSurfaceSelector():int
        {
            return _renderSurfaceSelector;
        }
        
        public function setRenderTarget( target:TextureBase, enableDepthAndStencil:Boolean = false, surfaceSelector:int = 0 ):void
        {
            if (_renderTarget == target && surfaceSelector == _renderSurfaceSelector && _enableDepthAndStencil == enableDepthAndStencil)
                return;
            _renderTarget = target;
            _renderSurfaceSelector = surfaceSelector;
            _enableDepthAndStencil = enableDepthAndStencil;
            
            if (target) _context3D.setRenderToTexture(target, enableDepthAndStencil, _antiAlias, surfaceSelector);
            else
                _context3D.setRenderToBackBuffer();
        }
        
        /*
         * Clear and reset the back buffer when using a shared context
         */
        public function clear():void
        {
            if (!_context3D) return;
            
            if (_backBufferDirty)
            {
                configureBackBuffer(_backBufferWidth, _backBufferHeight, _antiAlias);
                _backBufferDirty = false;
            }
            
            _context3D.clear(((_color >> 16) & 0xff) / 255.0, ((_color >> 8) & 0xff) / 255.0, (_color & 0xff) / 255.0, ((_color >> 24) & 0xff) / 255.0);
            
            _bufferClear = true;
        }
        
        /*
         * Display the back rendering buffer
         */
        public function present():void
        {
            if (!_context3D)
                return;
            
            _context3D.present();
            
            _activeProgram3D = null;
            
            if (_mouse3DManager) _mouse3DManager.fireMouseEvents();
        }
        
        /**
         * Registers an event listener object with an EventDispatcher object so that the listener receives notification of an event. Special case for enterframe and exitframe events - will switch Stage3DProxy into automatic render mode.
         * You can register event listeners on all nodes in the display list for a specific type of event, phase, and priority.
         *
         * @param type The type of event.
         * @param listener The listener function that processes the event.
         * @param useCapture Determines whether the listener works in the capture phase or the target and bubbling phases. If useCapture is set to true, the listener processes the event only during the capture phase and not in the target or bubbling phase. If useCapture is false, the listener processes the event only during the target or bubbling phase. To listen for the event in all three phases, call addEventListener twice, once with useCapture set to true, then again with useCapture set to false.
         * @param priority The priority level of the event listener. The priority is designated by a signed 32-bit integer. The higher the number, the higher the priority. All listeners with priority n are processed before listeners of priority n-1. If two or more listeners share the same priority, they are processed in the order in which they were added. The default priority is 0.
         * @param useWeakReference Determines whether the reference to the listener is strong or weak. A strong reference (the default) prevents your listener from being garbage-collected. A weak reference does not.
         */
        public override function addEventListener( type:String, listener:Function, useCapture:Boolean = false, priority:int = 0, useWeakReference:Boolean = false ):void
        {
            super.addEventListener(type, listener, useCapture, priority, useWeakReference);
            
            if ((type == Event.ENTER_FRAME || type == Event.EXIT_FRAME) && !_frameEventDriver.hasEventListener(Event.ENTER_FRAME)) _frameEventDriver.addEventListener(Event.ENTER_FRAME, onEnterFrame, useCapture, priority, useWeakReference);
        }
        
        /**
         * Removes a listener from the EventDispatcher object. Special case for enterframe and exitframe events - will switch Stage3DProxy out of automatic render mode.
         * If there is no matching listener registered with the EventDispatcher object, a call to this method has no effect.
         *
         * @param type The type of event.
         * @param listener The listener object to remove.
         * @param useCapture Specifies whether the listener was registered for the capture phase or the target and bubbling phases. If the listener was registered for both the capture phase and the target and bubbling phases, two calls to removeEventListener() are required to remove both, one call with useCapture() set to true, and another call with useCapture() set to false.
         */
        public override function removeEventListener( type:String, listener:Function, useCapture:Boolean = false ):void
        {
            super.removeEventListener(type, listener, useCapture);
            
            // Remove the main rendering listener if no EnterFrame listeners remain
            if (!hasEventListener(Event.ENTER_FRAME) && !hasEventListener(Event.EXIT_FRAME) && _frameEventDriver.hasEventListener(Event.ENTER_FRAME)) _frameEventDriver.removeEventListener(Event.ENTER_FRAME, onEnterFrame, useCapture);
        }
        
        public function get scissorRect():Rectangle
        {
            return _scissorRect;
        }
        
        public function set scissorRect( value:Rectangle ):void
        {
            _scissorRect = value;
            _context3D.setScissorRectangle(_scissorRect);
        }
        
        /**
         * The index of the Stage3D which is managed by this instance of Stage3DProxy.
         */
        public function get stage3DIndex():int
        {
            return _stage3DIndex;
        }
        
        /**
         * The base Stage3D object associated with this proxy.
         */
        public function get stage3D():Stage3D
        {
            return _stage3D;
        }
        
        /**
         * The Context3D object associated with the given Stage3D object.
         */
        public function get context3D():Context3D
        {
            return _context3D;
        }
        
        /**
         * The driver information as reported by the Context3D object (if any)
         */
        public function get driverInfo():String
        {
            return _context3D ? _context3D.driverInfo : null;
        }
        
        /**
         * Indicates whether the Stage3D managed by this proxy is running in software mode.
         * Remember to wait for the CONTEXT3D_CREATED event before checking this property,
         * as only then will it be guaranteed to be accurate.
         */
        public function get usesSoftwareRendering():Boolean
        {
            return _usesSoftwareRendering;
        }
        
        /**
         * The x position of the Stage3D.
         */
        public function get x():Number
        {
            return _stage3D.x;
        }
        
        public function set x( value:Number ):void
        {
            if (_viewPort.x == value)
                return;
            
            _stage3D.x = _viewPort.x = value;
            
            notifyViewportUpdated();
        }
        
        /**
         * The y position of the Stage3D.
         */
        public function get y():Number
        {
            return _stage3D.y;
        }
        
        public function set y( value:Number ):void
        {
            if (_viewPort.y == value)
                return;
            
            _stage3D.y = _viewPort.y = value;
            
            notifyViewportUpdated();
        }
        
        /**
         * The width of the Stage3D.
         */
        public function get width():int
        {
            return _backBufferWidth;
        }
        
        public function set width( width:int ):void
        {
            if (_viewPort.width == width)
                return;
            
            if (width < 50) width = 50;
            _backBufferWidth = _viewPort.width = width;
            _backBufferDirty = true;
            
            notifyViewportUpdated();
        }
        
        /**
         * The height of the Stage3D.
         */
        public function get height():int
        {
            return _backBufferHeight;
        }
        
        public function set height( height:int ):void
        {
            if (_viewPort.height == height)
                return;
            
            if (height < 50) height = 50;
            _backBufferHeight = _viewPort.height = height;
            _backBufferDirty = true;
            
            notifyViewportUpdated();
        }
        
        /**
         * The antiAliasing of the Stage3D.
         */
        public function get antiAlias():int
        {
            return _antiAlias;
        }
        
        public function set antiAlias( antiAlias:int ):void
        {
            _antiAlias = antiAlias;
            _backBufferDirty = true;
        }
        
        /**
         * A viewPort rectangle equivalent of the Stage3D size and position.
         */
        public function get viewPort():Rectangle
        {
            _viewportDirty = false;
            
            return _viewPort;
        }
        
        /**
         * The background color of the Stage3D.
         */
        public function get color():uint
        {
            return _color;
        }
        
        public function set color( color:uint ):void
        {
            _color = color;
        }
        
        /**
         * The visibility of the Stage3D.
         */
        public function get visible():Boolean
        {
            return _stage3D.visible;
        }
        
        public function set visible( value:Boolean ):void
        {
            _stage3D.visible = value;
        }
        
        /**
         * The freshly cleared state of the backbuffer before any rendering
         */
        public function get bufferClear():Boolean
        {
            return _bufferClear;
        }
        
        public function set bufferClear( newBufferClear:Boolean ):void
        {
            _bufferClear = newBufferClear;
        }
        
        /*
         * Access to fire mouseevents across multiple layered view3D instances
         */
        public function get mouse3DManager():Mouse3DManager
        {
            return _mouse3DManager;
        }
        
        public function set mouse3DManager( value:Mouse3DManager ):void
        {
            _mouse3DManager = value;
        }
        
        public function get touch3DManager():Touch3DManager
        {
            return _touch3DManager;
        }
        
        public function set touch3DManager( value:Touch3DManager ):void
        {
            _touch3DManager = value;
        }
        
        /**
         * Frees the Context3D associated with this Stage3DProxy.
         */
        private function freeContext3D():void
        {
            if (_context3D)
            {
                _context3D.dispose();
                dispatchEvent(new Stage3DEvent(Stage3DEvent.CONTEXT3D_DISPOSED));
            }
            _context3D = null;
        }
        
        /*
         * Called whenever the Context3D is retrieved or lost.
         * @param event The event dispatched.
         */
        private function onContext3DUpdate( event:Event ):void
        {
//			Utils.printStackTrace(event + " " + event.bubbles + "/" + event.currentTarget + "/" + event.type + "/" + event.cancelable);
			
            if (_stage3D.context3D)
            {
                var hadContext:Boolean = (_context3D != null);
                _context3D = _stage3D.context3D;
                _context3D.enableErrorChecking = Debug.active;
                
                _usesSoftwareRendering = (_context3D.driverInfo.indexOf("Software") == 0);
                
                // Only configure back buffer if width and height have been set,
                // which they may not have been if View3D.render() has yet to be
                // invoked for the first time.
                if (_backBufferWidth && _backBufferHeight) _context3D.configureBackBuffer(_backBufferWidth, _backBufferHeight, _antiAlias, _backBufferEnableDepthAndStencil);
				
				Utils.log("AWAY3D onContext3DUpdate driverInfo=" + _context3D.driverInfo + " _usesSoftwareRendering=" + _usesSoftwareRendering + " hadContext=" + hadContext);
                
                // Dispatch the appropriate event depending on whether context was
                // created for the first time or recreated after a device loss.
                dispatchEvent(new Stage3DEvent(hadContext ? Stage3DEvent.CONTEXT3D_RECREATED : Stage3DEvent.CONTEXT3D_CREATED));
            }
            else throw new Error("Rendering context lost!");
        }
        
		
		private var renderMode:String;
		private var profiles:Array;
		private var currentProfile:String;
		private var forceSoftware:Boolean;
		
        /**
         * Requests a Context3D object to attach to the managed Stage3D.
         */
        private function requestContext(forceSoftware:Boolean = false, profile:String = null ):void
        {
			this.forceSoftware = forceSoftware;
			
            // If forcing software, we can be certain that the
            // returned Context3D will be running software mode.
            // If not, we can't be sure and should stick to the
            // old value (will likely be same if re-requesting.)
            _usesSoftwareRendering ||= forceSoftware;
            _profile = profile;
            
            profiles = !profile ? [ //
                Context3DProfile.STANDARD_EXTENDED, //
                Context3DProfile.STANDARD, //
                Context3DProfile.STANDARD_CONSTRAINED, //
                Context3DProfile.BASELINE_EXTENDED, //
                Context3DProfile.BASELINE //
            ] : [profile];
            
            Utils.log("AWAY3D requestContext " + _profile + " " + _usesSoftwareRendering);
            
            addEventListener(Stage3DEvent.CONTEXT3D_CREATED, onCreated, false, 100);
			addEventListener(Stage3DEvent.CONTEXT3D_RECREATED, onRecreated, false, 100);
			
            stage3D.addEventListener(ErrorEvent.ERROR, onError, false, 100);
            
            requestNextProfile();
        }
		
        private function requestNextProfile():void
        {
            currentProfile = profiles.shift();
            renderMode = !currentProfile || forceSoftware ? Context3DRenderMode.SOFTWARE : Context3DRenderMode.AUTO;
            
            Utils.log("AWAY3D requestNextProfile " + currentProfile + " " + renderMode);
            
            try
            {
                stage3D.requestContext3D(renderMode, currentProfile);
            } 
			catch (err:Error)
            {
                if (!currentProfile)
                {
                    Utils.log(new AssukarError("unable to resolve context3D profile"), false);
                    throw new AssukarError(err.message, "unable to resolve context3D profile");
                }
                Utils.log("AWAY3D requestNextProfile TRYANOTHER");
                setTimeout(requestNextProfile, 1);
            }
        }
        
        private function onCreated( e:Stage3DEvent ):void
        {
            var context:Context3D = stage3D.context3D;
            Utils.log("AWAY3D onCreated " + (context?context.driverInfo:"") + " " + renderMode + " " + profiles.length);
            
            if (renderMode == Context3DRenderMode.AUTO && profiles.length != 0)
            {
                if (context.driverInfo.indexOf("Software") == -1)
                {
                    // accept this hardware profile.
                    accept();
                }
                else
                {
                    // context 3d resolution fell back on software. keep trying a hardware profile.
                    onError(e);
                }
            }
            else
            {
                // accept the given profile, probably software
                accept();
            }
        }
        
        private function accept():void
        {
            Utils.log("AWAY3D accept " + currentProfile);
            _profile = currentProfile;
            _contextRequested = true;
            onFinished();
        }
        
        private function onError( e:Event ):void
        {
            Utils.log("AWAY3D onError " + currentProfile + " " + e + " " + profiles.length);
            if (!currentProfile)
            {
                onFinished();
                Utils.log(new AssukarError("unable to resolve context3D profile"), false);
                throw new AssukarError("unable to resolve context3D profile");
            }
            e.stopImmediatePropagation();
            setTimeout(requestNextProfile, 1);
        }
		
		private function onRecreated( e:Stage3DEvent ):void
		{
            var context:Context3D = stage3D.context3D;
            Utils.log("AWAY3D onRecreated " + context + " " + (context ? context.driverInfo : "") + " " + renderMode);
		}
        
        private function onFinished():void
        {
			Utils.log("AWAY3D onFinished");
            stage3D.removeEventListener(Stage3DEvent.CONTEXT3D_CREATED, onCreated);
            stage3D.removeEventListener(ErrorEvent.ERROR, onError);
        }
        
        /**
         * The Enter_Frame handler for processing the proxy.ENTER_FRAME and proxy.EXIT_FRAME event handlers.
         * Typically the proxy.ENTER_FRAME listener would render the layers for this Stage3D instance.
         */
        private function onEnterFrame( event:Event ):void
        {
            if (!_context3D) return;
            
            // Clear the stage3D instance
            clear();
            
            //notify the enterframe listeners
            notifyEnterFrame();
            
            // Call the present() to render the frame
            present();
            
            //notify the exitframe listeners
            notifyExitFrame();
        }
        
        public function recoverFromDisposal():Boolean
        {
            if (!_context3D)
                return false;
            if (_context3D.driverInfo == "Disposed")
            {
                _context3D = null;
                dispatchEvent(new Stage3DEvent(Stage3DEvent.CONTEXT3D_DISPOSED));
                return false;
            }
            return true;
        }
        
        public function clearDepthBuffer():void
        {
            if (!_context3D)
                return;
            _context3D.clear(0, 0, 0, 1, 1, 0, Context3DClearMask.DEPTH);
        }
        
        public function get backBufferEnableDepthAndStencil():Boolean
        {
            return _backBufferEnableDepthAndStencil;
        }
        
        public function set backBufferEnableDepthAndStencil( value:Boolean ):void
        {
            _backBufferEnableDepthAndStencil = value;
            _backBufferDirty = true;
        }
    }
}

/*
 import com.assukar.airong.error.AssukarError;
 import com.assukar.airong.utils.Utils;
 
 import flash.display.Stage3D;
 import flash.display3D.Context3DProfile;
 import flash.display3D.Context3DRenderMode;
 import flash.utils.setTimeout;
 
 // pis0 24-04-2017
 class Context3DProfileResolver
 {
 private var profiles:Array = [ //
 Context3DProfile.STANDARD_EXTENDED, //
 Context3DProfile.STANDARD, //
 Context3DProfile.STANDARD_CONSTRAINED, //
 Context3DProfile.BASELINE_EXTENDED, //
 Context3DProfile.BASELINE //
 ];
 
 
 private var currentProfile:String = null;
 
 public function resolve(stage3D:Stage3D, callback:Function = null):void
 {
 currentProfile = profiles.shift();
 
 try
 {
 stage3D.requestContext3D(Context3DRenderMode.AUTO, currentProfile);
 if (callback!=null) callback(currentProfile);
 }
 catch (err:Error)
 {
 Utils.log("FAILED " + currentProfile + " " + err);
 if (profiles.length != 0) setTimeout(resolve, 1, stage3D, callback);
 else throw new AssukarError(err.message, "unable to resolve context3D profile");
 }
 }
 }
 */