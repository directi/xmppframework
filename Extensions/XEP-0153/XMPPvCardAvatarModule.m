//
//  XMPPvCardAvatarModule.h
//  XEP-0153 vCard-Based Avatars
//
//  Created by Eric Chamberlain on 3/9/11.
//  Copyright 2011 RF.com. All rights reserved.


// TODO: publish after upload vCard
/*
 * XEP-0153 Section 4.2 rule 1
 *
 * However, a client MUST advertise an image if it has just uploaded the vCard with a new avatar 
 * image. In this case, the client MAY choose not to redownload the vCard to verify its contents.
 */


#ifdef DEBUG_LEVEL
  #undef DEBUG_LEVEL
  #define DEBUG_LEVEL 1
#endif


#import "XMPPvCardAvatarModule.h"

#import "NSDataAdditions.h"
#import "NSXMLElementAdditions.h"
#import "XMPPPresence.h"
#import "XMPPvCardTempModule.h"

#import "ASIHTTPRequest.h"


NSString *const kXMPPvCardAvatarElement = @"x";
NSString *const kXMPPvCardAvatarNS = @"vcard-temp:x:update";
NSString *const kXMPPvCardAvatarPhotoElement = @"photo";


@implementation XMPPvCardAvatarModule


#pragma mark -
#pragma mark Init/dealloc methods


- (id)initWithvCardTempModule:(XMPPvCardTempModule *)xmppvCardTempModule {
	if ((self = [super initWithStream:xmppvCardTempModule.xmppStream])) {
    _xmppvCardTempModule = [xmppvCardTempModule retain];
    _moduleStorage = [(id <XMPPvCardAvatarStorage>)xmppvCardTempModule.moduleStorage retain];
    
    [_xmppvCardTempModule addDelegate:self];
	}
	return self;
}


- (void)dealloc {
  [_xmppvCardTempModule removeDelegate:self];
  
  [_moduleStorage release];
  _moduleStorage = nil;
  
  [_xmppvCardTempModule release];
  _xmppvCardTempModule = nil;
  
	[super dealloc];
}


#pragma mark - Public instance methods


- (NSData *)photoDataForJID:(XMPPJID *)jid {
  NSData *photoData = [_moduleStorage photoDataForJID:jid];
  
  if (photoData == nil) {
    [_xmppvCardTempModule fetchvCardTempForJID:jid xmppStream:xmppStream useCache:YES];
  }
  return photoData;
}


#pragma mark -
#pragma mark XMPPStreamDelegate methods


- (void)xmppStreamWillConnect:(XMPPStream *)sender {
  /* 
   * XEP-0153 Section 4.2 rule 1
   *
   * A client MUST NOT advertise an avatar image without first downloading the current vCard. 
   * Once it has done this, it MAY advertise an image. 
   */
  [_moduleStorage clearvCardTempForJID:[sender myJID]];
}


- (void)xmppStreamDidAuthenticate:(XMPPStream *)sender {
  [_xmppvCardTempModule fetchvCardTempForJID:[sender myJID] xmppStream:sender useCache:NO];
}


- (void)xmppStream:(XMPPStream *)sender willSendPresence:(XMPPPresence *)presence {  
  // add our photo info to the presence stanza

  // remove existing <x> element first
  NSXMLElement *xElement = [presence elementForName:kXMPPvCardAvatarElement xmlns:kXMPPvCardAvatarNS];
  if (xElement) {
    [xElement detach];
  }
  // create a new one now
  xElement = [NSXMLElement elementWithName:kXMPPvCardAvatarElement xmlns:kXMPPvCardAvatarNS];
  NSXMLElement *photoElement = nil;
  
  NSString *photoHash = [_moduleStorage photoHashForJID:[sender myJID]];
  
   if (photoHash != nil) {
     photoElement = [NSXMLElement elementWithName:kXMPPvCardAvatarPhotoElement stringValue:photoHash];
   } else {
     photoElement = [NSXMLElement elementWithName:kXMPPvCardAvatarPhotoElement];
   }
   
   [xElement addChild:photoElement];
   [presence addChild:xElement];
}


- (void)xmppStream:(XMPPStream *)sender didReceivePresence:(XMPPPresence *)presence  {
  NSXMLElement *xElement = [presence elementForName:kXMPPvCardAvatarElement xmlns:kXMPPvCardAvatarNS];
  
  if (xElement == nil) {
    return;
  }
  
  NSString *photoHash = [[xElement elementForName:kXMPPvCardAvatarPhotoElement] stringValue];
  
  if (photoHash == nil || [photoHash isEqualToString:@""]) {
    return;
  }
  
  XMPPJID *jid = [presence from];
  
  // check the hash
  if (![photoHash isEqualToString:[_moduleStorage photoHashForJID:jid]]) {
    [_xmppvCardTempModule fetchvCardTempForJID:jid xmppStream:sender useCache:NO];
  }
}


#pragma mark - Private method for received my avatar

- (void)didReceivePhoto:(NSData *)photo forJid:(XMPPJID *)jid {
  [multicastDelegate xmppvCardAvatarModule:self
                       didReceivePhotoData:photo
                                    forJID:jid];
  /*
	 * XEP-0153 4.1.3
	 * If the client subsequently obtains an avatar image (e.g., by updating or retrieving the vCard), 
	 * it SHOULD then publish a new <presence/> stanza with character data in the <photo/> element.
	 */

  if ([jid isEqual:[self.xmppStream.myJID bareJID]]) {
    //MyPresence is being released before it it set to the latest presence.
    //In this case, the only presence element was being released and so, errors were encountered.
    //Hence, presence should be retained for some time.
    XMPPPresence *presence = [self.xmppStream.myPresence retain];
    if (presence) {
      [self.xmppStream sendElement:presence];
    }
    [presence release];
  }
}


#pragma mark -
#pragma mark XMPPvCardTempModuleDelegate


- (void)xmppvCardTempModule:(XMPPvCardTempModule *)vCardTempModule 
        didReceivevCardTemp:(XMPPvCardTemp *)vCardTemp 
                     forJID:(XMPPJID *)jid
                 xmppStream:(XMPPStream *)aXmppStream {
  NSData *photo = vCardTemp.photo;
  if (photo == nil) {
    //Check for EXTVAL, an external URL.
    NSXMLElement *photoElement = [vCardTemp elementForName:@"PHOTO"];
    NSXMLElement *extval = [photoElement elementForName:@"EXTVAL"];
    
    if (extval) {
      //Fetch from the URL.
      NSURL *url = [NSURL URLWithString:[extval stringValue]];
      
      //Set user agent, otherwise, its getting too-many-redirection error.
      NSMutableDictionary *headers  = [NSMutableDictionary dictionaryWithCapacity:4];
      [headers setObject:@"Firefox" forKey:@"User-Agent"];
      
      ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:url];
      [request setDelegate:self];
      [request setRequestMethod:@"GET"];
      [request setRequestHeaders:headers];
      [request setNumberOfTimesToRetryOnTimeout:4];
      [request setUserInfo:[NSDictionary dictionaryWithObject:jid forKey:@"jid"]];
      [request setDidFinishSelector:@selector(fetchedPhoto:)];
      [request startAsynchronous];
    }
  }

  if (photo != nil) {
    [self didReceivePhoto:photo forJid:jid];
  }
}


#pragma mark - Get photo from external URL

- (void)fetchedPhoto:(ASIHTTPRequest *)request {
  NSData *photo = [request responseData];
  if ([photo length] == 0) {
    return;
  }
  [self didReceivePhoto:photo forJid:[request.userInfo objectForKey:@"jid"]];
}

#pragma mark -
#pragma mark Getter/setter methods


@synthesize xmppvCardTempModule = _xmppvCardTempModule;


@end
