// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
// 


#import <zmessaging/zmessaging.h>


@interface Message : NSObject

+ (BOOL)isTextMessage:(id<ZMConversationMessage>)message;
+ (BOOL)isImageMessage:(id<ZMConversationMessage>)message;
+ (BOOL)isKnockMessage:(id<ZMConversationMessage>)message;
+ (BOOL)isFileTransferMessage:(id<ZMConversationMessage>)message;
+ (BOOL)isVideoMessage:(id<ZMConversationMessage>)message;
+ (BOOL)isAudioMessage:(id<ZMConversationMessage>)message;
+ (BOOL)isLocationMessage:(id<ZMConversationMessage>)message;

+ (BOOL)isSystemMessage:(id<ZMConversationMessage>)message;
+ (BOOL)isNormalMessage:(id<ZMConversationMessage>)message;
+ (BOOL)isConnectionRequestMessage:(id<ZMConversationMessage>)message;
+ (BOOL)isMissedCallMessage:(id<ZMConversationMessage>)message;

+ (NSString *)formattedReceivedDateForMessage:(id<ZMConversationMessage>)message;
+ (NSString *)formattedReceivedDateLongVersion:(id<ZMConversationMessage>)message;
+ (NSString *)formattedDeletedDateForMessage:(id <ZMConversationMessage>)message;

+ (BOOL)isPresentableAsNotification:(id<ZMConversationMessage>)message;

@end
