

#import <Foundation/Foundation.h>
#import "MulticastDelegate.h"
#import "XMPPTransportProtocol.h"
#import "XMPPStream.h"
#import "NSXMLElementAdditions.h"
#import "XMPPSocketTransport.h"
#import "XMPPJID.h"

@class AsyncSocket;

@interface StanzaWithTag: NSObject<NSCoding>{
	NSString *stanza;
	NSInteger tag;
}

@property (readonly,nonatomic) NSString *stanza;
@property (nonatomic) int tag;

@end

@interface AcknowledgementQueue: NSObject<NSCoding> {
    
	NSMutableArray *stanzaQueue;
}

- (void) enqueueStanza:(NSString *)element withTag
                      :(int) tag;
- (void) dequeueStanzasTillTag:(int) maxTag;
- (NSArray *) stanzas;

@end

@interface XMPPResumableSocketTransport : XMPPSocketTransport<NSCoding> {
	BOOL brokenStream_;
	BOOL streamTagClosed;
	
	int sequenceNumberServer_;
	int sequenceNumberClient_;
	
	AcknowledgementQueue *acknowledgementQueue;
	
	int retryCounter;
	NSTimeInterval nextRequestDelay;
	
}

- (id)initWithCoder: (NSCoder *)coder;
- (void)encodeWithCoder: (NSCoder *)coder;


- (void)handleStanzaAcknowledgement:(NSXMLElement *)response;
- (void)acknowledgeReceivedStanzas:(NSXMLElement *)response; 

#pragma overriden methods
- (void)xmppParser:(XMPPParser *)sender didReadElement:(NSXMLElement *)element;
- (void)disconnect;
- (BOOL)sendStanzaWithString:(NSString *)string;
- (void)onSocketDidDisconnect:(AsyncSocket *)sock;
- (void)onSocket:(AsyncSocket *)socket didConnectToHost:(NSString *)givenHost port:(UInt16)givenPort;
- (void)onSocket:(AsyncSocket *)sock willDisconnectWithError:(NSError *)err;
- (void)xmppParser:(XMPPParser *)sender didReadRoot:(NSXMLElement *)root;

- (void)resendRemainingRequests;
@end