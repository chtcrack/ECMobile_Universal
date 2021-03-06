//
//   ______    ______    ______
//  /\  __ \  /\  ___\  /\  ___\
//  \ \  __<  \ \  __\_ \ \  __\_
//   \ \_____\ \ \_____\ \ \_____\
//    \/_____/  \/_____/  \/_____/
//
//
//  Copyright (c) 2014-2015, Geek Zoo Studio
//  http://www.bee-framework.com
//
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

#import "ServiceShare_Weixin.h"

#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR)

#pragma mark -

@interface ServiceShare_Weixin()
{
	NSNumber *						_errorCode;
	NSString *						_errorDesc;
	ServiceShare_Weixin_Config *	_config;
}

- (BOOL)checkInstalled;
- (void)share:(enum WXScene)scene;
- (void)openWeixin;
- (void)openStore;

- (void)clearPost;
- (void)clearError;

@end

#pragma mark -

@implementation ServiceShare_Weixin

SERVICE_AUTO_LOADING( YES )
SERVICE_AUTO_POWERON( YES )

DEF_SINGLETON( ServiceShare_Weixin )

DEF_NUMBER( ERROR_NOT_INSTALL, -100 )
DEF_NUMBER( ERROR_NOT_SUPPORT, -101 )

@synthesize config = _config;

@dynamic ready;
@dynamic installed;
@synthesize errorCode = _errorCode;
@synthesize errorDesc = _errorDesc;

@dynamic SHARE_TO_FRIEND;
@dynamic SHARE_TO_TIMELINE;

@dynamic OPEN_WEIXIN;
@dynamic OPEN_STORE;

- (void)load
{
//	[super load];
	
	self.state = self.STATE_IDLE;
	self.config = [[[ServiceShare_Weixin_Config alloc] init] autorelease];

	self.whenAuthBegin		= [ServiceShare sharedInstance].whenAuthBegin;
	self.whenAuthSucceed	= [ServiceShare sharedInstance].whenAuthSucceed;
	self.whenAuthFailed		= [ServiceShare sharedInstance].whenAuthFailed;
	self.whenAuthCancelled	= [ServiceShare sharedInstance].whenAuthCancelled;
	
	self.whenShareBegin		= [ServiceShare sharedInstance].whenShareBegin;
	self.whenShareSucceed	= [ServiceShare sharedInstance].whenShareSucceed;
	self.whenShareFailed	= [ServiceShare sharedInstance].whenShareFailed;
	self.whenShareCancelled	= [ServiceShare sharedInstance].whenShareCancelled;
}

- (void)unload
{
	self.config = nil;
	
//	[super unload];
}

#pragma mark -

- (void)powerOn
{
	BOOL succeed = [WXApi registerApp:self.config.appId];
	if ( NO == succeed )
	{
		ERROR( @"Failed to register weixin app '%@'", self.config.appId );
	}

	[super powerOn];
}

- (void)powerOff
{
	[self clearError];
	[self clearPost];
	
	[super powerOff];
}

- (void)serviceWillActive
{
	[super serviceWillActive];

	if ( self.launchParameters )
	{
		NSURL * url			= [self.launchParameters objectForKey:@"url"];
		NSString * source	= [self.launchParameters objectForKey:@"source"];

		if ( [[url absoluteString] hasSuffix:@"wechat"] || [source hasPrefix:@"com.tencent.xin"] )
		{
			BOOL succeed = [WXApi handleOpenURL:url delegate:self];
			if ( NO == succeed )
			{
				if ( self.STATE_IDLE != self.state )
				{
					[self notifyShareCancelled];
				}
			}
		}
		else
		{
			if ( self.STATE_IDLE != self.state )
			{
				[self notifyShareCancelled];
			}
		}
	}
	else
	{
		if ( self.STATE_IDLE != self.state )
		{
			[self notifyShareCancelled];
		}
	}
}

- (void)serviceDidActived
{
	[super serviceDidActived];
}

- (void)serviceWillDeactive
{
	[super serviceWillDeactive];
}

- (void)serviceDidDeactived
{
	[super serviceDidDeactived];
}

#pragma mark -

- (BOOL)ready
{
	if ( self.config.appId && self.config.appKey )
	{
		return YES;
	}

	return NO;
}

- (BOOL)installed
{
	return [WXApi isWXAppInstalled];
}

- (BeeServiceBlock)SHARE_TO_FRIEND
{
	BeeServiceBlock block = ^ void ( void )
	{
		[self share:WXSceneSession];
	};
	
	return [[block copy] autorelease];
}

- (BeeServiceBlock)SHARE_TO_TIMELINE
{
	BeeServiceBlock block = ^ void ( void )
	{
		[self share:WXSceneTimeline];
	};
	
	return [[block copy] autorelease];
}

- (BeeServiceBlock)OPEN_WEIXIN
{
	BeeServiceBlock block = ^ void ( void )
	{
		[self openWeixin];
	};
	
	return [[block copy] autorelease];
}

- (BeeServiceBlock)OPEN_STORE
{
	BeeServiceBlock block = ^ void ( void )
	{
		[self openStore];
	};
	
	return [[block copy] autorelease];
}

#pragma mark -

- (BOOL)checkInstalled
{
	BOOL installed = [WXApi isWXAppInstalled];
	if ( NO == installed )
	{
		self.errorCode = self.ERROR_NOT_INSTALL;
		self.errorDesc = @"Please install weixin";
		return NO;
	}

	BOOL support = [WXApi isWXAppSupportApi];
	if ( NO == support )
	{
		self.errorCode = self.ERROR_NOT_SUPPORT;
		self.errorDesc = @"Version too old";
		return NO;
	}

	return YES;
}

- (void)share:(enum WXScene)scene
{
	BOOL result = [self checkInstalled];
	if ( NO == result )
	{
		[self notifyShareFailed];
		return;
	}

	if ( self.post.photo || self.post.thumb || self.post.url )
	{
		SendMessageToWXReq *	req = [[[SendMessageToWXReq alloc] init] autorelease];
		WXMediaMessage *		message = [WXMediaMessage message];

		if ( self.post.thumb )
		{
			NSData * thumbData = nil;

			if ( [self.post.thumb isKindOfClass:[UIImage class]] )
			{
				thumbData = [(UIImage *)self.post.thumb dataWithExt:@"png"];
			}
			else if ( [self.post.thumb isKindOfClass:[NSString class]] )
			{
				thumbData = [NSData dataWithContentsOfURL:[NSURL URLWithString:(NSString *)self.post.thumb]];
			}
			else if ( [self.post.thumb isKindOfClass:[NSData class]] )
			{
				thumbData = (NSData *)self.post.thumb;
			}

			[message setThumbData:thumbData];
		}
		
		if ( self.post.photo )
		{
			WXImageObject * imageObject = [WXImageObject object];

			if ( [self.post.photo isKindOfClass:[UIImage class]] )
			{
				imageObject.imageData = [(UIImage *)self.post.photo dataWithExt:@"png"];
			}
			else if ( [self.post.photo isKindOfClass:[NSString class]] )
			{
				imageObject.imageUrl = (NSString *)self.post.photo;
			}
			
			message.mediaObject = imageObject;
		}
		
		if ( self.post.url )
		{
			WXWebpageObject * webObject = [WXWebpageObject object];

			webObject.webpageUrl = self.post.url;

			message.mediaObject = webObject;
		}

		if ( self.post.title && self.post.title.length )
		{
			if ( WXSceneTimeline == scene )
			{
				message.title = self.post.text;
			}
			else
			{
				message.title = self.post.title;
			}
		}

		if ( self.post.text && self.post.text.length )
		{
			message.description = self.post.text;
		}
		
		req.message = message;
		req.bText = NO;
		req.scene = scene;
		
		BOOL succeed = [WXApi sendReq:req];
		if ( succeed )
		{
			[self notifyShareBegin];
		}
		else
		{
			[self notifyShareFailed];
		}
	}
	else if ( self.post.text )
	{
		SendMessageToWXReq * req = [[[SendMessageToWXReq alloc] init] autorelease];

		if ( self.post.title && self.post.title.length )
		{
			req.text = self.post.title;
		}
		
		if ( self.post.text && self.post.text.length )
		{
			req.text = self.post.text;
		}
		
		req.bText = YES;
		req.scene = scene;
		
		BOOL succeed = [WXApi sendReq:req];
		if ( succeed )
		{
			[self notifyShareBegin];
		}
		else
		{
			[self notifyShareFailed];
		}
	}
	else
	{
		[self notifyShareFailed];
	}
}

- (void)openWeixin
{
	[WXApi openWXApp];
}

- (void)openStore
{
#if !TARGET_IPHONE_SIMULATOR

	NSString * url = [WXApi getWXAppInstallUrl];
	if ( url && url.length )
	{
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
	}

#endif	// #if !TARGET_IPHONE_SIMULATOR
}

- (void)clearPost
{
	[self.post clear];
}

- (void)clearError
{
	self.errorCode = nil;
	self.errorDesc = nil;
}

#pragma mark -

- (void)notifyShareBegin
{
	self.state = self.STATE_SHARING;

	if ( self.whenShareBegin )
	{
		self.whenShareBegin();
	}
	else if ( [ServiceShare sharedInstance].whenShareBegin )
	{
		[ServiceShare sharedInstance].whenShareBegin();
	}
}

- (void)notifyShareSucceed
{
	if ( self.whenShareSucceed )
	{
		self.whenShareSucceed();
	}
	else if ( [ServiceShare sharedInstance].whenShareSucceed )
	{
		[ServiceShare sharedInstance].whenShareSucceed();
	}

	[self clearError];
	[self clearPost];
	
	self.state = self.STATE_IDLE;
}

- (void)notifyShareFailed
{
	ERROR( @"Failed to share, errorCode = %@, errorDesc = %@", self.errorCode, self.errorDesc );

	if ( self.whenShareFailed )
	{
		self.whenShareFailed();
	}
	else if ( [ServiceShare sharedInstance].whenShareFailed )
	{
		[ServiceShare sharedInstance].whenShareFailed();
	}

	[self clearPost];

	self.state = self.STATE_IDLE;
}

- (void)notifyShareCancelled
{
	if ( self.whenShareCancelled )
	{
		self.whenShareCancelled();
	}
	else if ( [ServiceShare sharedInstance].whenShareCancelled )
	{
		[ServiceShare sharedInstance].whenShareCancelled();
	}

	[self clearPost];
	
	self.state = self.STATE_IDLE;
}

#pragma mark - WXApiDelegate

- (void)onReq:(BaseReq*)req
{
    
}

- (void)onResp:(BaseResp*)resp
{
    if ( [resp isKindOfClass:[SendMessageToWXResp class]] )
    {
        if ( WXSuccess == resp.errCode )
        {
			[self notifyShareSucceed];
		}
		else if ( WXErrCodeUserCancel == resp.errCode )
		{
			[self notifyShareCancelled];
		}
		else
		{
			self.errorCode = [NSNumber numberWithInt:resp.errCode];
			self.errorDesc = resp.errStr;
			
			[self notifyShareFailed];
		}
    }
}

@end

#endif	// #if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR)
