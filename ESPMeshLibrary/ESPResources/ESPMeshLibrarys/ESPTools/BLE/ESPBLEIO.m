//
//  BabyBLEIO.m
//  OznerLibrarySwifty
//
//  Created by 赵兵 on 2016/12/27.
//  Copyright © 2016年 net.ozner. All rights reserved.
//

#import "ESPBLEIO.h"
#import "PacketCommand.h"
#import "DH_AES.h"

#import "ESPDataConversion.h"
#import "DH_AES.h"

#import "HGBRSAEncrytor.h"

enum ConfigureNumber {
    
    ConfigureSuccess = 300,
    connectSuccessful,
    bleConnected,
    foundWriteCharacteristic,
    writeData,
    notificationSuccessful,
    configureData,
    NegotiateSecurity,
    DeviceConnected,
    PeripheralStateConnected,
};

@interface ESPBLEIO (){
@private
    BOOL requireWifiState;
}

@property(nonatomic,assign) BOOL HasSendNegotiateDataWithDevice;
@property(nonatomic,assign) BOOL HasSendNegotiateDataWithNewDevice;
@property(nonatomic,strong) RSAObject *rsaobject;
@property(nonatomic,assign) uint8_t channel;
@property(nonatomic, strong)NSMutableData *ESP32data;
@property(nonatomic, assign)NSInteger length;

@end
@implementation ESPBLEIO

{
    //CBService* curService;
    CBCharacteristic* writeCharacteristic;
    CBCharacteristic* readCharacteristic;
    NSString *ssid;
    NSString *password;
    EspDevice *Device;
    NSData* meshID;
    NSData* bssID;
    NSData* whiteList;
    NSDictionary *infoDic;
    NSMutableArray *sendTypeArr;
    NSMutableArray *sendLengthArr;
    
    //传入的原始数据
    EspDevice* originalDevice;
    //NSMutableDictionary* originalInfo;
    NSDate* starPairDate;
    NSTimer* outTimer;
    NSInteger timeout;
    bool canSendMsg;
}
NSString* idString;
- (instancetype)init:(EspDevice*)device pairInfo:(NSMutableDictionary*)info timeOut:(NSInteger)timeOut callBackBlock:(BLEIOCallBackBlock)callBackBlock {
    self = [super init];
    if (self) {
        canSendMsg=true;
        timeout=timeOut;
        [outTimer invalidate];
        outTimer=nil;
        outTimer=[NSTimer scheduledTimerWithTimeInterval:timeOut target:self selector:@selector(disconnectBLE) userInfo:nil repeats:false];
        [[NSRunLoop currentRunLoop] addTimer:outTimer forMode:NSDefaultRunLoopMode];
        
        starPairDate=[NSDate date];
        originalDevice=device;
        infoDic = info;
        idString=device.uuidBle;
        ssid=info[@"ssid"];
        password=info[@"password"];
        NSString *bssidStr = info[@"bssid"];
        NSArray *bssidArr = [bssidStr componentsSeparatedByString:@":"];
        uint8_t bssidByte[6];
        for (int i = 0; i < bssidArr.count; i ++) {
            const char *hexChar = [[NSString stringWithFormat:@"%@",bssidArr[i]] cStringUsingEncoding:NSUTF8StringEncoding];
            int hexNumber;
            sscanf(hexChar, "%x", &hexNumber);
            bssidByte[i] = hexNumber;
        }
        bssID=[[NSData alloc] initWithBytes:bssidByte length:6];
        NSArray* meshidArr=info[@"mesh_id"];
        uint8_t meshidByte[6];
        for (int i=0; i<meshidArr.count; i++) {
            meshidByte[i]=[NSString stringWithFormat:@"%@",meshidArr[i]].intValue;
        }
        meshID=[[NSData alloc] initWithBytes:meshidByte length:6];
        NSArray* whiteListArr=info[@"white_list"];
        uint8_t tmpWhiteList[6*whiteListArr.count];
        for (int i=0; i<whiteListArr.count; i++) {
            NSString* macStr=[NSString stringWithFormat:@"%@",whiteListArr[i]];
            for (int j=0; j<(macStr.length/2); j++) {
                NSString* subStr=[macStr substringWithRange:NSMakeRange(j*2, 2)];
                const char *hexChar = [subStr cStringUsingEncoding:NSUTF8StringEncoding];
                int hexNumber;
                sscanf(hexChar, "%x", &hexNumber);
                tmpWhiteList[i*6+j]=hexNumber;
            }
        }
        whiteList=[[NSData alloc] initWithBytes:tmpWhiteList length:6*whiteListArr.count];
        _CallBackBlock=callBackBlock;
        //初始化BabyBluetooth 蓝牙库
        baby = [BabyBluetooth shareBabyBluetooth];
        [baby cancelAllPeripheralsConnection];
        [self babyDelegate];//设置蓝牙委托
        [self restarPair];
        
    }
    return self;
    
}
//断开链接
- (void)disconnectBLE{
    //[baby cancelNotify:self.currPeripheral characteristic:readCharacteristic];
    [baby AutoReconnectCancel:self.currPeripheral];
    [baby cancelAllPeripheralsConnection];
}
//删除自动重连
- (void)AutoReconnectCancel:(CBPeripheral *)peripheral {
    [baby AutoReconnectCancel:peripheral];
}

//重新开始配网
-(void)restarPair{
    [self disconnectBLE];
    requireWifiState=YES;
    _HasSendNegotiateDataWithDevice=false;
    self.ESP32data=[NSMutableData data];
    self.length=0;
    Device=originalDevice;
    if ([Device.version isEqualToString:[NSString stringWithFormat:@"-1"]]) {
        _HasSendNegotiateDataWithNewDevice = false;
    }else{
        _HasSendNegotiateDataWithNewDevice = true;
    }
    [self performSelector:@selector(loadData) withObject:nil afterDelay:1.5];
}

-(void)loadData{
    
    if (baby.centralManager.state==CBCentralManagerStatePoweredOn) {

        self.currPeripheral=[baby retrievePeripheralWithUUIDString:idString];//获取外设
        if (self.currPeripheral==nil) {
            [self updateMessage:@"error:retrievePeripheralWithUUIDString failed:-60"];
            return;
        }
        
        
      [baby AutoReconnect:self.currPeripheral];
    baby.having(self.currPeripheral).and.channel(idString).then.connectToPeripherals().discoverServices().discoverCharacteristics().readValueForCharacteristic().discoverDescriptorsForCharacteristic().readValueForDescriptors().begin();
 
        switch (self.currPeripheral.state) {//初始化设备状态
            case CBPeripheralStateConnected:
                
                [self updateMessage:[NSString stringWithFormat:@"msg:CBPeripheralStateConnected:%d",PeripheralStateConnected]];
                break;
            case CBPeripheralStateDisconnected:
             
                [self updateMessage:@"error:CBPeripheralStateDisconnected:-61"];
                break;
            default:
                break;
        }
        
    
    } else {
        [self updateMessage:@"error:CBCentralManagerStatePoweredOff:-62"];
    }
    
}

-(void)babyDelegate{
    __weak typeof(self)weakSelf = self;
    
    [baby setBlockOnCentralManagerDidUpdateState:^(CBCentralManager *central) {
        [weakSelf loadData];
    }];
    [baby setBlockOnCentralManagerDidUpdateStateAtChannel:idString block:^(CBCentralManager *central) {
        [weakSelf loadData];
    }];
    
    //设置设备连接成功的委托,同一个baby对象，使用不同的channel切换委托回调
    [baby setBlockOnConnectedAtChannel:idString block:^(CBCentralManager *central, CBPeripheral *peripheral) {
        if (![idString isEqualToString:peripheral.identifier.UUIDString]) {
            return ;
        }
        //取消自动回连功能(连接成功后必须清除自动回连,否则会崩溃)
        [weakSelf AutoReconnectCancel:weakSelf.currPeripheral];
        [weakSelf updateMessage:[NSString stringWithFormat:@"msg:connect  successful:%d",connectSuccessful]];
        
    }];
    weakSelf.ESP32data=NULL;
    weakSelf.length=0;
    //设置设备连接失败的委托
    [baby setBlockOnFailToConnectAtChannel:idString block:^(CBCentralManager *central, CBPeripheral *peripheral, NSError *error) {
        if (![idString isEqualToString:peripheral.identifier.UUIDString]) {
            return ;
        }
        [weakSelf updateMessage:@"error:connect  Fail:-63"];
    }];
    [baby setBlockOnConnectedAtChannel:idString block:^(CBCentralManager *central, CBPeripheral *peripheral) {
        if (![idString isEqualToString:peripheral.identifier.UUIDString]) {
            return ;
        }
        [weakSelf updateMessage:[NSString stringWithFormat:@"msg:ble connected:%d",bleConnected]];
    }];
    //设置设备断开连接的委托
    [baby setBlockOnDisconnectAtChannel:idString block:^(CBCentralManager *central, CBPeripheral *peripheral, NSError *error) {
        if (![idString isEqualToString:peripheral.identifier.UUIDString]) {
            return ;
        }
        weakSelf.HasSendNegotiateDataWithDevice=false;
        self->writeCharacteristic=nil;
        self->readCharacteristic =nil;
        [weakSelf updateMessage:@"error:Disconnect:-64"];
    }];
    
    //设置发现设service的Characteristics的委托
    [baby setBlockOnDiscoverCharacteristicsAtChannel:idString block:^(CBPeripheral *peripheral, CBService *service, NSError *error) {
        if (![idString isEqualToString:peripheral.identifier.UUIDString]) {
            return ;
        }
        if (![service.UUID.UUIDString isEqualToString:@"FFFF"]) {
            return;
        }
        if (self->writeCharacteristic  && self->readCharacteristic ) {
            return;
        }
        
        
        for (CBCharacteristic* characteristic in service.characteristics)
        {
            if ([[[characteristic UUID] UUIDString] isEqualToString:@"FF01"])
            {
                self->writeCharacteristic=characteristic;
            }
            if ([[[characteristic UUID] UUIDString] isEqualToString:@"FF02"])
            {
                self->readCharacteristic=characteristic;
            }
            if (self->writeCharacteristic  && self->readCharacteristic ) {
               
                [weakSelf updateMessage:[NSString stringWithFormat:@"msg:found writeCharacteristic，readCharacteristic:%d",foundWriteCharacteristic]];
                [weakSelf setNotifiy];
                break;
            }
        }
        
        
    }];
    

    
    //设置写数据成功的block
    [baby setBlockOnDidWriteValueForCharacteristicAtChannel:idString block:^(CBCharacteristic *characteristic, NSError *error) {
        [weakSelf updateMessage:[NSString stringWithFormat:@"msg:write data ok:%d",writeData]];
    }];


    //characteristic订阅状态改变的block
    [baby setBlockOnDidUpdateNotificationStateForCharacteristicAtChannel:idString block:^(CBCharacteristic *characteristic, NSError *error) {
        if (weakSelf.HasSendNegotiateDataWithDevice) {
            return ;
        }
        if (!error) {
            if (characteristic.isNotifying) {
                [weakSelf updateMessage:[NSString stringWithFormat:@"msg:Set notification successful:%d",notificationSuccessful]];
                weakSelf.HasSendNegotiateDataWithDevice = true;
                if (weakSelf.HasSendNegotiateDataWithNewDevice) {
                    [weakSelf SendNegotiateDataWithNewDevice];
                }else{
                    [weakSelf SendNegotiateDataWithDevice];
                }
            } else {
                [weakSelf updateMessage:@"error:BLE set notify failed:-65"];
                
            }
        } else {
            NSLog(@"BLE update notification error %@", error);
            
            [weakSelf updateMessage:@"error:Notification state error:-6"];
       
        }
    }];
    //扫描选项->CBCentralManagerScanOptionAllowDuplicatesKey:忽略同一个Peripheral端的多个发现事件被聚合成一个发现事件
    NSDictionary *scanForPeripheralsWithOptions = @{CBCentralManagerScanOptionAllowDuplicatesKey:@YES};
    NSDictionary *connectOptions = @{CBConnectPeripheralOptionNotifyOnConnectionKey:@NO,
                                     CBConnectPeripheralOptionNotifyOnDisconnectionKey:@NO,
                                     CBConnectPeripheralOptionNotifyOnNotificationKey:@NO};
    
    [baby setBabyOptionsAtChannel:idString scanForPeripheralsWithOptions:scanForPeripheralsWithOptions connectPeripheralWithOptions:connectOptions scanForPeripheralsWithServices:nil discoverWithServices:nil discoverWithCharacteristics:nil];
}
//订阅一个值
//int Notified=0;
-(void)setNotifiy{
    __weak typeof(self)weakSelf = self;
    if (self->readCharacteristic.properties & CBCharacteristicPropertyNotify ||  self->readCharacteristic.properties & CBCharacteristicPropertyIndicate) {
        
        if(!readCharacteristic.isNotifying) {
            
            [weakSelf.currPeripheral setNotifyValue:YES forCharacteristic:self->readCharacteristic];
        
            [baby notify:self.currPeripheral
          characteristic:self->readCharacteristic
                   block:^(CBPeripheral *peripheral, CBCharacteristic *characteristics, NSError *error) {
                       //订阅蓝牙数据返回
                       if (error) {
                           [weakSelf updateMessage:@"error:ble data callback error:-66"];
                           
                       } else {
                           NSLog(@">>>>>>>>>收到蓝牙数据：%@",characteristics.value);
                           [weakSelf analyseData:[NSMutableData dataWithData:characteristics.value]];
                       }
                   }];
        }
    }
    else{
        [weakSelf updateMessage:@"error:characteristic nofity limits:-67"];
        return;
    }
    
}

- (void)updateMessage:(NSString *)message {
    if (canSendMsg) {
        self.CallBackBlock(message);
        NSArray *messageArr = [message componentsSeparatedByString:@":"];
        if([messageArr[0] containsString:@"error"]||[messageArr[0] containsString:@"success"]||[messageArr[0] containsString:@"code"]){
            canSendMsg=false;
            [self disconnectBLE];
        }
    }
    
}

- (void)writeStructDataWithDevice:(NSData *)data {
    if (_currPeripheral!=nil && writeCharacteristic!=nil) {
        NSLog(@"<<<<<<<<蓝牙发送数据：%@",data);
        [_currPeripheral writeValue:data forCharacteristic:writeCharacteristic type:CBCharacteristicWriteWithResponse];
        Device.sequence = Device.sequence + 1;
    } else {
        [self updateMessage:@"error:peripheral write characteristic nil:-68"];
    }
}

- (void)analyseData:(NSMutableData *)data {
    Byte *dataByte = (Byte *)[data bytes];
    Byte Type = dataByte[0] & 0x03;
    Byte SubType=dataByte[0]>>2;
    Byte sequence = dataByte[2];
    Byte frameControl = dataByte[1];
    Byte length = dataByte[3];
    BOOL hash = frameControl & Packet_Hash_FrameCtrlType;
    BOOL checksum = frameControl & Data_End_Checksum_FrameCtrlType;
    //BOOL Drection=frameControl & Data_Direction_FrameCtrlType;
    BOOL Ack=frameControl & ACK_FrameCtrlType;
    BOOL AppendPacket=frameControl & Append_Data_FrameCtrlType;
    NSRange range=NSMakeRange(4, length);
    NSData *encryptdata=[data subdataWithRange:range];
    NSData *Decryptdata;
    if (hash) {
        NSLog(@"加密");
        //解密
        NSRange range = NSMakeRange(4, length);
//        NSData *Decryptdata = [data subdataWithRange:range];
        Byte *byte = (Byte *)[encryptdata bytes];
        Decryptdata = [DH_AES blufi_aes_DecryptWithSequence:sequence data:byte len:length KeyData:Device.Securtkey];
        [data replaceBytesInRange:range withBytes:[Decryptdata bytes]];
    } else {
        NSLog(@"无加密");
        Decryptdata = encryptdata;
    }
    if (checksum) {
        if (length+6 != data.length) {
            return;
        }
        NSLog(@"有校验");
        //计算校验
        if ([PacketCommand VerifyCRCWithData:data]) {
            NSLog(@"校验成功");
        } else {
            NSLog(@"校验失败,返回");
            [self updateMessage:@"error:CRC error:-69"];
            return;
        }
    } else {
        NSLog(@"无校验");
        if (length+4 != data.length) {
            return;
        }
    }
    if (Ack) {
        NSLog(@"回复ACK");
        [self writeStructDataWithDevice:[PacketCommand ReturnAckWithSequence:Device.sequence BackSequence:sequence] ];
    } else {
        NSLog(@"不回复ACK");
    }
    NSMutableData *decryptdata=[NSMutableData dataWithData:Decryptdata];
    if (AppendPacket) {
        NSLog(@"有后续包");
        [decryptdata replaceBytesInRange:NSMakeRange(0, 2) withBytes:NULL length:0];
        //拼包
        if(self.ESP32data){
            [self.ESP32data appendData:decryptdata];
        }else{
            self.ESP32data=[NSMutableData dataWithData:decryptdata];
        }
        self.length=self.length+length;
        return;
    } else {
        NSLog(@"没有后续包");
        if(self.ESP32data){
            [self.ESP32data appendData:decryptdata];
            decryptdata =[NSMutableData dataWithData:self.ESP32data];
            self.ESP32data=NULL;
            length = self.length+length;
            self.length=0;
        }
    }
    
    if (Type == ContolType) {
        //NSLog(@"接收到控制包===========");
        [self GetControlPacketWithData:decryptdata SubType:SubType];
    } else if (Type==DataType) {
        //NSLog(@"接收到数据包===========");
        [self GetDataPackectWithData:decryptdata SubType:SubType];
    } else if (Type == UserType){
        //自定义用户包
        [self GetUserPacketWithData:decryptdata SubType:SubType];
    } else {
        [self updateMessage:@"error:analyse data error:-70"];
    }
}

//用户包解析
-(void)GetUserPacketWithData:(NSData *)data SubType:(Byte)subType {
    Byte *dataByte = (Byte *)[data bytes];
    switch (subType) {
        case 0x00:
            self.channel=dataByte[0];
            if (Device.index == 1) {
                //连接wifi
                [self writeStructDataWithDevice:[PacketCommand ConnectToAPWithSequence:Device.sequence]];
            }
        default:
            break;
    }
}

//控制包解析
-(void)GetControlPacketWithData:(NSData *)data SubType:(Byte)subType {
    switch (subType) {
        case ACK_Esp32_Phone_ControlSubType:
            NSLog(@"Receive ACK ,%@", Device.name);
            Device.blufisuccess = YES;
            [self updateMessage:[NSString stringWithFormat:@"msg:Post configure data complete:%d",configureData]];
            if (!requireWifiState) {
                [self updateMessage:[NSString stringWithFormat:@"success:pair:%d",ConfigureSuccess]];
            }
            break;
        case ESP32_Phone_Security_ControlSubType:
        case Wifi_Op_ControlSubType:
        case Connect_AP_ControlSubType:
        case Disconnect_AP_ControlSubType:
        case Get_Wifi_Status_ControlSubType:
        case Deauthenticate_STA_Device_SoftAP_ControlSubType:
        case Get_Version_ControlSubType:
        case Negotiate_Data_ControlSubType:
            break;
        default:
            break;
    }
}

//数据包解析
-(void)GetDataPackectWithData:(NSData *)data SubType:(Byte)subType {
    Byte *dataByte = (Byte *)[data bytes];
//    for (int i = 0; i < data.length; i++) {
//        NSLog(@"DataByte[%d]:%d", i, dataByte[i]);
//    }
    NSLog(@"subType--------------->%hhu",subType);
    
    switch (subType) {
        case Negotiate_Data_DataSubType: //协商数据
            {
                NSLog(@"Receive negoriate data");
                if (self.HasSendNegotiateDataWithNewDevice) {
                    NSString *dataStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    NSLog(@"%@",dataStr);
                    NSLog(@"%@",[dataStr componentsSeparatedByString:@"-"].lastObject);
                    Device.Securtkey = [self sendPrivateKeyToDevice:data];
                }else{
                    Device.Securtkey = [DH_AES GetSecurtKey:data RsaObject:self.rsaobject];
                }
                [self updateMessage:[NSString stringWithFormat:@"msg:Negotiate security complete:%d",NegotiateSecurity]];
                //设置加密模式
                NSData *SetSecuritydata=[PacketCommand SetESP32ToPhoneSecurityWithSecurity:YES CheckSum:YES Sequence:Device.sequence];
                [self writeStructDataWithDevice:SetSecuritydata];

                [self sendOpmode];
                
                if (self.HasSendNegotiateDataWithNewDevice) {
                    //新设备配网
                    [self sendNewDistributionNetworkData];
                }else{
                    //旧设备配网
                    [self sendDistributionNetworkData];
                }
            }
            break;
        case Wifi_Connection_state_Report_DataSubType: //连接状态报告
            NSLog(@"Notify wifi state");
            Byte opMode = dataByte[0];
            NSLog(@"OP Mode %d", opMode);
            if (opMode != STAOpmode) {
                [self updateMessage:[NSString stringWithFormat:@"error:Wifi opmode %d:-71", opMode]];
                return;
            }
            Byte stationConn = dataByte[1];
            NSLog(@"Wifi state %d", stationConn);
            BOOL connectWifi = stationConn == 0;
            if (!connectWifi) {
                [self updateMessage:@"error:Device connect wifi failed:-20"];
                return;
            }
            [self updateMessage:[NSString stringWithFormat:@"msg:Device connected wifi:%d",DeviceConnected]];
      
            [self updateMessage:[NSString stringWithFormat:@"success:pair:%d",ConfigureSuccess]];
            break;
        case Error_DataSubType:
       
            NSLog(@"%@",data);
            if (data.length==0) {
                [self updateMessage:@"error:notify data error:-72"];
            } else  {
                [self updateMessage:[NSString stringWithFormat:@"code:notify code:%d", dataByte[0]]];
            }
            break;
        case BSSID_STA_DataSubType:
        case SSID_STA_DataSubType:
        case Password_STA_DataSubType:
        case SSID_SoftaAP_DataSubType:
        case Password_SoftAP_DataSubType:
        case Max_Connect_Number_SoftAP_DataSubType:
        case Authentication_SoftAP_DataSubType:
        case Channel_SoftAP_DataSubType:
        case Username_DataSubType:
        case CA_Certification_DataSubType:
        case Client_Certification_DataSubType:
        case Server_Certification_DataSubType:
        case Client_PrivateKey_DataSubType:
        case Server_PrivateKey_DataSubType:
        case Version_DataSubType:
            break;
        default:
            break;
    }
}

- (void)sendeDataRestructuring:(NSString *)typeMessage withKeyMessage:(NSString *)keyMessage {
    
    if ([infoDic objectForKey:keyMessage] && ![[infoDic objectForKey:keyMessage] isEqual: [NSNull null]]) {
        [sendTypeArr addObject:typeMessage];
        [sendLengthArr addObject:[infoDic objectForKey:keyMessage]];
    }
}

//发送新设备配网数据
- (void)sendNewDistributionNetworkData {
    NSMutableData *sendData = [[NSMutableData alloc]init];
    uint8_t type[1];
    uint8_t length[1];
    sendTypeArr = [NSMutableArray arrayWithCapacity:0];
    sendLengthArr = [NSMutableArray arrayWithCapacity:0];
    NSArray *typeArr = @[@"0",@"1",@"2",@"5",@"6",@"16",@"17",@"18",@"19",@"20",@"21",@"22",@"23",@"24",@"25",@"26",@"27",@"28",@"29",@"30",@"31",@"32",@"33",@"34",@"35",@"36",@"37"];
    NSArray *lengthArr = @[@"custom_data",@"ssid",@"password",@"mesh_password",@"mesh_type",@"vote_percentage",@"vote_max_count",@"backoff_rssi",@"scan_min_count",@"scan_fail_count",@"monitor_ie_count",@"root_healing_ms",@"root_conflicts_enable",@"fix_root_enable",@"capacity_num",@"max_layer",@"max_connection",@"assoc_expire_ms",@"beacon_interval_ms",@"passive_scan_ms",@"monitor_duration_ms",@"cnx_rssi",@"select_rssi",@"switch_rssi",@"xon_qsize",@"retransmit_enable",@"data_drop_enable"];
    for (int i = 0; i < typeArr.count; i ++) {
        [self sendeDataRestructuring:typeArr[i] withKeyMessage:lengthArr[i]];
    }
    for (int i = 0; i < sendTypeArr.count; i ++) {
        type[0] = [sendTypeArr[i] intValue];
        [sendData appendData:[[NSData alloc]initWithBytes:type length:sizeof(type)]];
        NSString *lengthStr = sendLengthArr[i];
    
        if ([lengthStr isEqual:@(NO)]) {
            length[0] = 1;
            [sendData appendData:[[NSData alloc]initWithBytes:length length:sizeof(length)]];
            Byte data[1] = {0};
            [sendData appendBytes:data length:1];
        }else if ([lengthStr isEqual:@(YES)]) {
            length[0] = 1;
            [sendData appendData:[[NSData alloc]initWithBytes:length length:sizeof(length)]];
            Byte data[1] = {0};
            [sendData appendBytes:data length:1];
        }else {
            length[0] = lengthStr.length;
            [sendData appendData:[[NSData alloc]initWithBytes:length length:sizeof(length)]];
            [sendData appendData:[lengthStr dataUsingEncoding:NSUTF8StringEncoding]];
        }
        
        
        
    }
    type[0] = 3;
    length[0] = bssID.length;
    [sendData appendData:[[NSData alloc]initWithBytes:type length:sizeof(type)]];
    [sendData appendData:[[NSData alloc]initWithBytes:length length:sizeof(length)]];
    [sendData appendData:bssID];
    
    type[0] = 4;
    length[0] = meshID.length;
    [sendData appendData:[[NSData alloc]initWithBytes:type length:sizeof(type)]];
    [sendData appendData:[[NSData alloc]initWithBytes:length length:sizeof(length)]];
    [sendData appendData:meshID];
    
    int macGroupCount=ceil(whiteList.length/240.0);
    for (int i=0; i<macGroupCount; i++) {
        if (macGroupCount-1==i) {
            length[0] = whiteList.length%240==0? 240:whiteList.length%240;
        }else{//240
            length[0] = 240;
        }
        type[0] = 64;
        [sendData appendData:[[NSData alloc]initWithBytes:type length:sizeof(type)]];
        [sendData appendData:[[NSData alloc]initWithBytes:length length:sizeof(length)]];
        
        [sendData appendData:[whiteList subdataWithRange:(NSRange){i*240,length[0]}]];
    }
    
    NSLog(@"%@",sendData);
    if (meshID) {
        NSInteger datacount = 80;
        //发送数据,需要分包
        Device.senddata = sendData;
        NSInteger number = Device.senddata.length / datacount + ((Device.senddata.length % datacount)>0? 1:0);
        BOOL EncryptBool = Device.Securtkey ? YES:NO;
        for(NSInteger i = 0; i < number; i++){
            if (i == number-1){
                NSData *data = [PacketCommand SetMeshID:Device.senddata Sequence:Device.sequence Frag:NO Device:YES Encrypt:EncryptBool TotalLength:Device.senddata.length WithKeyData:Device.Securtkey];
                [self writeStructDataWithDevice:data];
            } else {
                NSData *data = [PacketCommand SetMeshID:[Device.senddata subdataWithRange:NSMakeRange(0, datacount)] Sequence:Device.sequence Frag:YES Device:YES Encrypt:EncryptBool TotalLength:Device.senddata.length WithKeyData:Device.Securtkey];
                [self writeStructDataWithDevice:data];
                
                Device.senddata = [Device.senddata subdataWithRange:NSMakeRange(datacount, Device.senddata.length-datacount)];
            }
        }
        
    }
    
}

- (void)sendOpmode {
    uint8_t dataBytes[1];
    dataBytes[0]=0x01;
    NSMutableData *datas=[NSMutableData dataWithBytes:&dataBytes length:sizeof(dataBytes)];
    Device.senddata = datas;
    NSData *data=[PacketCommand SendOpmode:Device.senddata Sequence:Device.sequence];
    [self writeStructDataWithDevice:data];
    
}

//发送旧设备配网数据
- (void)sendDistributionNetworkData {
    NSMutableData *sendData = [[NSMutableData alloc]init];
    uint8_t type[1];
    uint8_t length[1];
    
    type[0] = 0x01;
    [sendData appendData:[[NSData alloc]initWithBytes:type length:sizeof(type)]];
    length[0] = ssid.length;
    [sendData appendData:[[NSData alloc]initWithBytes:length length:sizeof(length)]];
    [sendData appendData:[ssid dataUsingEncoding:NSUTF8StringEncoding]];
    
    type[0] = 0x02;
    [sendData appendData:[[NSData alloc]initWithBytes:type length:sizeof(type)]];
    length[0] = password.length;
    [sendData appendData:[[NSData alloc]initWithBytes:length length:sizeof(length)]];
    [sendData appendData:[password dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSLog(@"meshID---send-->%@",meshID);
    type[0] = 0x03;
    length[0] = meshID.length;
    [sendData appendData:[[NSData alloc]initWithBytes:type length:sizeof(type)]];
    [sendData appendData:[[NSData alloc]initWithBytes:length length:sizeof(length)]];
    [sendData appendData:meshID];
    
    
    type[0] = 0x04; // User Token 16 bytes
    Byte tokenByte[] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};//临时
    NSData *tokenData = [[NSData alloc] initWithBytes:tokenByte length:16];
    length[0] = tokenData.length;
    [sendData appendData:[[NSData alloc]initWithBytes:type length:sizeof(type)]];
    [sendData appendData:[[NSData alloc]initWithBytes:length length:sizeof(length)]];
    [sendData appendData:tokenData];
    
    int macGroupCount=ceil(whiteList.length/240.0);
    for (int i=0; i<macGroupCount; i++) {
        if (macGroupCount-1==i) {
            length[0] = whiteList.length%240==0? 240:whiteList.length%240;
        }else{//240
            length[0] = 240;
        }
        type[0] = 0x05;
        [sendData appendData:[[NSData alloc]initWithBytes:type length:sizeof(type)]];
        [sendData appendData:[[NSData alloc]initWithBytes:length length:sizeof(length)]];
        
        [sendData appendData:[whiteList subdataWithRange:(NSRange){i*240,length[0]}]];
    }
    
    NSLog(@"%@",sendData);
    if (meshID) {
        NSInteger datacount = 80;
        //发送数据,需要分包
        Device.senddata = sendData;
        NSInteger number = Device.senddata.length / datacount + ((Device.senddata.length % datacount)>0? 1:0);
        BOOL EncryptBool = Device.Securtkey ? YES:NO;
        for(NSInteger i = 0; i < number; i++){
            if (i == number-1){
                 NSData *data = [PacketCommand SetMeshID:Device.senddata Sequence:Device.sequence Frag:NO Device:NO Encrypt:EncryptBool TotalLength:Device.senddata.length WithKeyData:Device.Securtkey];
                [self writeStructDataWithDevice:data];
            } else {
                NSData *data = [PacketCommand SetMeshID:[Device.senddata subdataWithRange:NSMakeRange(0, datacount)] Sequence:Device.sequence Frag:YES Device:NO Encrypt:EncryptBool TotalLength:Device.senddata.length WithKeyData:Device.Securtkey];
                [self writeStructDataWithDevice:data];
                
                Device.senddata = [Device.senddata subdataWithRange:NSMakeRange(datacount, Device.senddata.length-datacount)];
            }
        }
        
    }
}
//旧设备加密协议商定
-(void)SendNegotiateDataWithDevice{
    if (!self.rsaobject) {
        self.rsaobject = [DH_AES DHGenerateKey];
    }
    NSInteger datacount = 139;
    //发送数据长度
    uint16_t length = self.rsaobject.P.length + self.rsaobject.g.length + self.rsaobject.PublickKey.length+6;
    [self writeStructDataWithDevice:[PacketCommand SetNegotiatelength:length Sequence:Device.sequence]];
    
    //发送数据,需要分包
    Device.senddata = [PacketCommand GenerateNegotiateData:self.rsaobject];
    NSInteger number = Device.senddata.length / datacount + ((Device.senddata.length % datacount)>0? 1:0);

    for(NSInteger i = 0; i < number; i++){
        if (i == number-1){
            NSData *data=[PacketCommand SendNegotiateData:Device.senddata Sequence:Device.sequence Frag:NO TotalLength:Device.senddata.length];
            [self writeStructDataWithDevice:data];
        } else {
            NSData *data = [PacketCommand SendNegotiateData:[Device.senddata subdataWithRange:NSMakeRange(0, datacount)] Sequence:Device.sequence Frag:YES TotalLength:Device.senddata.length];
            [self writeStructDataWithDevice:data];
            Device.senddata = [Device.senddata subdataWithRange:NSMakeRange(datacount, Device.senddata.length-datacount)];
        }
    }
}

//新设备加密协议商定
- (void)SendNegotiateDataWithNewDevice {
    uint8_t dataBytes[1];
    dataBytes[0]=0x10;
    NSMutableData *datas=[NSMutableData dataWithBytes:&dataBytes length:sizeof(dataBytes)];
    Device.senddata = datas;
    NSData *data=[PacketCommand SendNewNegotiateData:Device.senddata Sequence:Device.sequence];
    [self writeStructDataWithDevice:data];
}
//发送密钥给设备
- (NSData *)sendPrivateKeyToDevice:(NSData *)publicKey {
    NSMutableData *sendData = [[NSMutableData alloc]init];
    
    uint8_t dataBytes[1];
    dataBytes[0]=0x11;
    NSMutableData *datas=[NSMutableData dataWithBytes:&dataBytes length:sizeof(dataBytes)];
    [sendData appendData:datas];
    
    NSString *keyStr = [ESPDataConversion getRandomAESKey];
    NSLog(@"keyStr16--->%@",keyStr);
    //16位随机数
    NSData *keyData = [keyStr dataUsingEncoding:NSUTF8StringEncoding];
    NSLog(@"keyData--->%@",keyData);
    NSString *dataStr = [[NSString alloc] initWithData:publicKey encoding:NSUTF8StringEncoding];
    NSData *randomAESKeyData = [HGBRSAEncrytor encryptData:keyData withPublicKey:dataStr];
    NSLog(@"randomAESKeyData--->%@",randomAESKeyData);
    [sendData appendData:randomAESKeyData];
    
    NSInteger datacount = 80;
    //发送数据,需要分包
    Device.senddata = sendData;
    NSInteger number = Device.senddata.length / datacount + ((Device.senddata.length % datacount)>0? 1:0);
    for(NSInteger i = 0; i < number; i++){
        if (i == number-1){
            NSData *data = [PacketCommand SendKeyToDevice:Device.senddata Sequence:Device.sequence Frag:NO TotalLength:Device.senddata.length];
            [self writeStructDataWithDevice:data];
        } else {
            NSData *data = [PacketCommand SendKeyToDevice:[Device.senddata subdataWithRange:NSMakeRange(0, datacount)] Sequence:Device.sequence Frag:YES TotalLength:Device.senddata.length];
            [self writeStructDataWithDevice:data];
            Device.senddata = [Device.senddata subdataWithRange:NSMakeRange(datacount, Device.senddata.length-datacount)];
        }
    }
    
    return keyData;
}

@end

