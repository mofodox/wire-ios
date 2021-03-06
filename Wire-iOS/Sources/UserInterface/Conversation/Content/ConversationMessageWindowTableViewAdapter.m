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


#import "ConversationMessageWindowTableViewAdapter.h"
#import "ZMConversationMessageWindow+Formatting.h"
#import "NSIndexSet+IndexPaths.h"
#import "Analytics+iOS.h"
#import "NSIndexSet+IndexPaths.h"

// Cells
#import "TextMessageCell.h"
#import "ImageMessageCell.h"
#import "NameChangedCell.h"
#import "PingCell.h"
#import "MissedCallCell.h"
#import "ConnectionRequestCell.h"
#import "EmptyCell.h"

#import "Wire-Swift.h"



static NSString *const ConversationNameChangedCellId        = @"ConversationNameChangedCell";
static NSString *const ConversationTextCellId               = @"ConversationTextCell";
static NSString *const ConversationImageCellId              = @"ConversationImageCell";
static NSString *const ConversationConnectionRequestCellId  = @"ConversationConnectionRequestCellId";
static NSString *const ConversationUnknownCellId            = @"ConversationUnkownCell";
static NSString *const ConversationMissedCallCellId         = @"ConversationMissedCallCell";
static NSString *const ConversationPingCellId               = @"conversationPingCellId";
static NSString *const ConversationNewDeviceCellId          = @"ConversationNewDeviceCellId";
static NSString *const ConversationVerifiedCellId           = @"conversationVerifiedCellId";
static NSString *const ConversationMissingMessagesCellId    = @"conversationMissingMessagesCellId";
static NSString *const ConversationIgnoredDeviceCellId      = @"conversationIgnoredDeviceCellId";
static NSString *const ConversationCannotDecryptCellId      = @"conversationCannotDecryptCellId";
static NSString *const ConversationFileTransferCellId       = @"conversationFileTransferCellId";
static NSString *const ConversationVideoMessageCellId       = @"conversationVideoMessageCellId";
static NSString *const ConversationAudioMessageCellId       = @"conversationAudioMessageCellId";
static NSString *const ConversationParticipantsCellId       = @"conversationParticipantsCellId";
static NSString *const ConversationLocationMessageCellId    = @"conversationLocationMessageCellId";
static NSString *const ConversationMessageDeletedCellId     = @"conversationMessageDeletedCellId";



@interface ConversationMessageWindowTableViewAdapter () <ZMConversationMessageWindowObserver>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) ZMConversationMessageWindow *messageWindow;
@property (nonatomic) id <ZMConversationMessageWindowObserverOpaqueToken> messageWindowObserverToken;
@property (nonatomic) NSMutableDictionary *cellLayoutPropertiesCache;
@property (nonatomic) BOOL expandingWindow;

@end



@implementation ConversationMessageWindowTableViewAdapter

- (instancetype)initWithTableView:(UITableView *)tableView messageWindow:(ZMConversationMessageWindow *)messageWindow
{
    self = [super init];
    
    if (self) {
        self.tableView = tableView;
        self.messageWindow = messageWindow;
        self.messageWindowObserverToken = [self.messageWindow addConversationWindowObserver:self];
        
        [self updateLastUnreadMessage];
        [self registerTableCellClasses];
    }
    
    return self;
}

- (void)dealloc
{
    if (self.messageWindowObserverToken != nil) {
        [self.messageWindow removeConversationWindowObserverToken:self.messageWindowObserverToken];
    }
}

- (void)updateLastUnreadMessage
{
    ZMMessage *lastReadMessage = self.messageWindow.conversation.lastReadMessage;
    NSUInteger lastReadIndex = [self.messageWindow.messages indexOfObject:lastReadMessage];
    
    if (lastReadIndex != NSNotFound && lastReadIndex > 0) {
        self.lastUnreadMessage = [self.messageWindow.messages objectAtIndex:lastReadIndex - 1];
    } else {
        self.lastUnreadMessage = nil;
    }
    
}

#pragma mark - ZMConversationMessageWindowObserver

- (void)conversationWindowDidChange:(MessageWindowChangeInfo *)change
{
    BOOL initialContentLoad = self.messageWindow.messages.count == change.insertedIndexes.count && change.deletedIndexes.count == 0;
    BOOL updateOnlyChange = change.insertedIndexes.count == 0 && change.deletedIndexes.count == 0 && change.movedIndexPairs.count == 0;
    BOOL insertionAtTop = change.insertedIndexes.count > 0 && change.insertedIndexes.lastIndex == self.messageWindow.messages.count - 1;
    
    if (initialContentLoad || insertionAtTop) {
        [self.tableView reloadData];
    }
    else if (! updateOnlyChange) {
        [self.tableView beginUpdates];
        
        if (change.deletedIndexes.count) {
            [self.tableView deleteRowsAtIndexPaths:[change.deletedIndexes indexPaths] withRowAnimation:UITableViewRowAnimationFade];
        }
        
        if (change.insertedIndexes.count) {
            [self.tableView insertRowsAtIndexPaths:[change.insertedIndexes indexPaths] withRowAnimation:UITableViewRowAnimationFade];
        }
        
        [change.movedIndexPairs enumerateObjectsUsingBlock:^(ZMMovedIndex *moved, NSUInteger idx, BOOL *stop) {
            NSIndexPath *from = [NSIndexPath indexPathForRow:moved.from inSection:0];
            NSIndexPath *to = [NSIndexPath indexPathForRow:moved.to inSection:0];
            [self.tableView moveRowAtIndexPath:from toIndexPath:to];
        }];
        
        // Unless a message was appended to the bottom of the conversation we need re-configure the cells
        // since they might (not) need to display an name & avatar after the insertion/deletion/move.
        BOOL messageWasInsertedAtBottom = change.insertedIndexes.count == 1 && change.insertedIndexes.firstIndex == 0;
        if (! messageWasInsertedAtBottom || change.deletedIndexes.count > 0 || change.movedIndexPairs.count > 0) {
            [self reconfigureVisibleCells];
        }
        
        [self.tableView endUpdates];
    }
}

- (void)reconfigureVisibleCells
{
    for (ConversationCell *cell in self.tableView.visibleCells) {
        
        if (! [cell isKindOfClass:ConversationCell.class]) {
            continue;
        }
        
        [self configureConversationCell:cell withMessage:cell.message];
    }
}

- (void)messagesInsideWindowDidChange:(NSArray *)messageChangeInfos
{
    BOOL needsToLayoutCells = NO;
    
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        if ([cell isKindOfClass:[ConversationCell class]]) {
            ConversationCell *conversationCell = (ConversationCell *)cell;
            
            for (MessageChangeInfo *changeInfo in messageChangeInfos) {
                if ([changeInfo.message isEqual:conversationCell.message]) {
                    needsToLayoutCells |= [conversationCell updateForMessage:changeInfo];
                }
            }
        }
    }
    
    if (needsToLayoutCells) {
        // Make table view to update cells with animation
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.messageWindow.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    id<ZMConversationMessage>message = [self.messageWindow.messages objectAtIndex:indexPath.row];
    
    NSString *cellIdentifier = ConversationUnknownCellId;
    
    if ([Message isTextMessage:message]) {
        cellIdentifier = ConversationTextCellId;
    }
    else if ([Message isVideoMessage:message]) {
        cellIdentifier = ConversationVideoMessageCellId;
    }
    else if ([Message isAudioMessage:message]) {
        cellIdentifier = ConversationAudioMessageCellId;
    }
    else if ([Message isLocationMessage:message]) {
        cellIdentifier = ConversationLocationMessageCellId;
    }
    else if ([Message isFileTransferMessage:message]) {
        cellIdentifier = ConversationFileTransferCellId;
    }
    else if ([Message isImageMessage:message]) {
        cellIdentifier = ConversationImageCellId;
    }
    else if ([Message isKnockMessage:message]) {
        cellIdentifier = ConversationPingCellId;
    }
    else if ([Message isSystemMessage:message]) {
        
        switch (message.systemMessageData.systemMessageType) {
                
            case ZMSystemMessageTypeConnectionRequest:
                cellIdentifier = ConversationConnectionRequestCellId;
                break;
                
            case ZMSystemMessageTypeConnectionUpdate:
                break;
                
            case ZMSystemMessageTypeConversationNameChanged:
                cellIdentifier = ConversationNameChangedCellId;
                break;
                
            case ZMSystemMessageTypeMissedCall:
                cellIdentifier = ConversationMissedCallCellId;
                break;
                
            case ZMSystemMessageTypeNewClient:
            case ZMSystemMessageTypeUsingNewDevice:
                cellIdentifier = ConversationNewDeviceCellId;
                break;
                
            case ZMSystemMessageTypeIgnoredClient:
                cellIdentifier = ConversationIgnoredDeviceCellId;
                break;
                
            case ZMSystemMessageTypeConversationIsSecure:
                cellIdentifier = ConversationVerifiedCellId;
                break;
                
            case ZMSystemMessageTypePotentialGap:
            case ZMSystemMessageTypeReactivatedDevice:
                cellIdentifier = ConversationMissingMessagesCellId;
                break;
                
            case ZMSystemMessageTypeDecryptionFailed:
            case ZMSystemMessageTypeDecryptionFailed_RemoteIdentityChanged:
                cellIdentifier = ConversationCannotDecryptCellId;
                break;
                
            case ZMSystemMessageTypeParticipantsAdded:
            case ZMSystemMessageTypeParticipantsRemoved:
            case ZMSystemMessageTypeNewConversation:
                cellIdentifier = ConversationParticipantsCellId;
                break;
                
            case ZMSystemMessageTypeMessageDeletedForEveryone:
                cellIdentifier = ConversationMessageDeletedCellId;

            default:
                break;
        }
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier forIndexPath:indexPath];
    
    ConversationCell *conversationCell = nil;
    if ([cell isKindOfClass:ConversationCell.class]) {
        conversationCell = (ConversationCell *)cell;
    }
    
    conversationCell.delegate = self.conversationCellDelegate;
    conversationCell.analyticsTracker = self.analyticsTracker;
    
    [self configureConversationCell:conversationCell withMessage:message];
    
    return cell;
}

- (void)configureConversationCell:(ConversationCell *)conversationCell withMessage:(id<ZMConversationMessage>)message
{
    // If a message has been deleted we don't try to configure it
    if (message.hasBeenDeleted) {return; }
    
    ConversationCellLayoutProperties *layoutProperties = [self.messageWindow layoutPropertiesForMessage:message lastUnreadMessage:self.lastUnreadMessage];
    
    conversationCell.selected = [message isEqual:self.selectedMessage];
    [conversationCell configureForMessage:message layoutProperties:layoutProperties];
}

- (void)registerTableCellClasses
{
    [self.tableView registerClass:[TextMessageCell class] forCellReuseIdentifier:ConversationTextCellId];
    [self.tableView registerClass:[ImageMessageCell class] forCellReuseIdentifier:ConversationImageCellId];
    [self.tableView registerClass:[NameChangedCell class] forCellReuseIdentifier:ConversationNameChangedCellId];
    [self.tableView registerClass:[PingCell class] forCellReuseIdentifier:ConversationPingCellId];
    [self.tableView registerClass:[MissedCallCell class] forCellReuseIdentifier:ConversationMissedCallCellId];
    [self.tableView registerClass:[ConnectionRequestCell class] forCellReuseIdentifier:ConversationConnectionRequestCellId];
    [self.tableView registerClass:[ConversationNewDeviceCell class] forCellReuseIdentifier:ConversationNewDeviceCellId];
    [self.tableView registerClass:[ConversationVerifiedCell class] forCellReuseIdentifier:ConversationVerifiedCellId];
    [self.tableView registerClass:[MissingMessagesCell class] forCellReuseIdentifier:ConversationMissingMessagesCellId];
    [self.tableView registerClass:[ConversationIgnoredDeviceCell class] forCellReuseIdentifier:ConversationIgnoredDeviceCellId];
    [self.tableView registerClass:[CannotDecryptCell class] forCellReuseIdentifier:ConversationCannotDecryptCellId];
    [self.tableView registerClass:[FileTransferCell class] forCellReuseIdentifier:ConversationFileTransferCellId];
    [self.tableView registerClass:[VideoMessageCell class] forCellReuseIdentifier:ConversationVideoMessageCellId];
    [self.tableView registerClass:[AudioMessageCell class] forCellReuseIdentifier:ConversationAudioMessageCellId];
    [self.tableView registerClass:[ConversationParticipantsCell class] forCellReuseIdentifier:ConversationParticipantsCellId];
    [self.tableView registerClass:[LocationMessageCell class] forCellReuseIdentifier:ConversationLocationMessageCellId];
    [self.tableView registerClass:[MessageDeletedCell class] forCellReuseIdentifier:ConversationMessageDeletedCellId];

    // unknown message types
    [self.tableView registerClass:[EmptyCell class] forCellReuseIdentifier:ConversationUnknownCellId];
}

- (void)expandMessageWindow
{
    if (! self.expandingWindow) {
        self.expandingWindow = YES;
        
        [self.messageWindow moveUpByMessages:25];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.expandingWindow = NO;
        });
    }
}

@end
