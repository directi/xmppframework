//
//  PausableMockClass.m
//  Talkto
//
//  Created by pushpraj agrawal on 11/11/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "PausableMockClass.h"


@implementation PausableMockClass

@synthesize originalClass;
@synthesize isPaused;

- (void)pause {
  if ( !self.isPaused ) {
    self.isPaused = TRUE;
    
    self -> isa = [PausableMockClass class];
  }
}

- (void)resume {
  if ( self.isPaused ) {
    self.isPaused = FALSE;
    
    self -> isa = [self.originalClass class];
  }
}


- (BOOL)respondsToSelector:(SEL)aSelector {
  return [self.originalClass respondsToSelector:aSelector];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
  return [self.originalClass instanceMethodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
  NSLog(@"Error: calling method on proxied object For %@",self.originalClass);
}


@end
