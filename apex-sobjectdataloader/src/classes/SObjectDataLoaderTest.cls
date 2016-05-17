/**
 * Copyright (c) 2012, Andrew Fawcett
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification, 
 *   are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice, 
 *      this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice, 
 *      this list of conditions and the following disclaimer in the documentation 
 *      and/or other materials provided with the distribution.
 * - Neither the name of the Andrew Fawcett, inc nor the names of its contributors 
 *      may be used to endorse or promote products derived from this software without 
 *      specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL 
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**/

/**
 * Test class for SObjectDataLoader
 *
 *   See https://github.com/afawcett/apex-sobjectdataloader for known issues, restrictions and TODO's
 *
 **/
@isTest
private class SObjectDataLoaderTest { 
    /**
     * Test implemetnation of IDeserializeCallback, automatically applies Standard Pricebook to new PricebookEntry's
     **/
    private class ApplyStandardPricebook implements SObjectDataLoader.IDeserializeCallback
    {
        private Id standardPricebookId;
        
        public ApplyStandardPricebook()
        {
            standardPricebookId = Test.getStandardPricebookId();                
        }
        
        public void unresolvedReferences(Schema.SObjectType sObjectType, List<SObjectDataLoader.UnresolvedReferences> unresolvedReferences)
        {
            if(sObjectType == PricebookEntry.sObjectType) // PricebookEntry object?
                for(SObjectDataLoader.UnresolvedReferences unresolvedReference : unresolvedReferences)
                    if(unresolvedReference.References.contains(PricebookEntry.Pricebook2Id)) // Pricebook2Id field?
                        unresolvedReference.Record.put(PricebookEntry.Pricebook2Id, standardPricebookId); // Set Standard Pricebook
        }       
    }
    
    private static void assertResults(Set<ID> opportunityIds)
    {
        Id pbId = Test.getStandardPricebookId();
        List<Opportunity> opportunities = 
            [select Id, Name, Amount, 
                (select id, PricebookEntry.Product2.Name, PricebookEntry.Pricebook2Id, UnitPrice 
                 from OpportunityLineItems 
                 order by PricebookEntry.Product2.Name) 
                from Opportunity 
                where Id in :opportunityIds 
                order by Name];
        System.assertEquals(10, opportunities.size());
        System.assertEquals('Test Name 0', opportunities[0].Name);
        System.assertEquals(10, opportunities[0].Amount);
        System.assertEquals('Test Name 9', opportunities[9].Name);
        System.assertEquals(100, opportunities[9].Amount);      
        System.assertEquals(1, opportunities[0].OpportunityLineItems.size());
        System.assertEquals(10, opportunities[0].OpportunityLineItems[0].UnitPrice);
        System.assertEquals('Test Name 0 : Product : 0', opportunities[0].OpportunityLineItems[0].PricebookEntry.Product2.Name);
        System.assertEquals(pbId, opportunities[0].OpportunityLineItems[0].PricebookEntry.Pricebook2Id);
        System.assertEquals(10, opportunities[9].OpportunityLineItems.size());
        System.assertEquals(10, opportunities[9].OpportunityLineItems[0].UnitPrice);
        System.assertEquals('Test Name 9 : Product : 9', opportunities[9].OpportunityLineItems[9].PricebookEntry.Product2.Name);
        System.assertEquals(pbId, opportunities[9].OpportunityLineItems[9].PricebookEntry.Pricebook2Id);        
    }

    /**
        --Without Blacklisting RecordTypeId, the autoconfig serialize/deserialize
            will try to insert a new RecordType object which throws:
            'System.TypeException: DML not allowed on RecordType'

        --Test uses dynamic binding to prevent compile-time errors in orgs without RecordTypes enabled
        --Currently, the test method only tests the logic if there are 2+ RecordTypes on the Account object
            otherwise, the if statement will silently ignore the rest of the testMethod.
    **/

    @isTest(seeAllData=False)
    private static void shouldNotTryToInsertRecordType(){
        List<RecordType> accountRecordTypes = [SELECT Id, DeveloperName FROM RecordType WHERE sObjectType = 'Account' AND isActive = TRUE];
        //Only run this test if there are multiple active recordtypes on Account object
        if (accountRecordTypes.size() > 0){
            Set<Id> availableRecordTypeIdSet = new Set<Id>();

            Schema.DescribeSObjectResult R = Account.SObjectType.getDescribe();
            List<Schema.RecordTypeInfo> RT = R.getRecordTypeInfos();
            for (Schema.RecordTypeInfo recordType : RT) {
                if (recordType.isAvailable() && !recordType.isMaster()) {
                    availableRecordTypeIdSet.add(recordType.getRecordTypeId());
                }
            }

            List<sObject> testAccounts = new List<Account>();
            for (RecordType aRT : accountRecordTypes){
                sObject testAccount = new Account(Name = 'Test' + aRT.DeveloperName);
                
                //dynamic binding will prevent any compile time errors if RecordTypeId field doesn't exist
                testAccount.put('RecordTypeId', aRT.Id);
                testAccounts.add(testAccount);
            }
            insert testAccounts;
            Set<Id> newAccountIds = new Set<Id>();
            for (sObject myAccount : testAccounts){
                newAccountIds.add(myAccount.Id);
            }
            String serializedData = SObjectDataLoader.serialize(newAccountIds);
            Set<Id> resultIds = SObjectDataLoader.deserialize(serializedData);
            
            //dynamic soql will prevent any compile time errors if RecordTypeId field doesn't exist
            String accountsQuery = 'SELECT Id, RecordTypeId FROM Account WHERE Id IN :newAccountIds';
            testAccounts = Database.query(accountsQuery);
            Set<Id> recordTypeIdsOfNewAccounts = new Set<Id>();

            for (sObject myAccount : testAccounts){
                recordTypeIdsOfNewAccounts.add((Id) myAccount.get('RecordTypeId'));
            }
            system.assertEquals(availableRecordTypeIdSet.size(), recordTypeIdsOfNewAccounts.size());
        }
    }

@isTest(seeAllData=False)
    private static void deserializingObjectsWithSelfRefernces(){
        Account testParentAccount = new Account(Name = 'ParentAccount');
        insert testParentAccount;
        Account childAccount = new Account();
        childAccount.ParentId =testParentAccount.Id;
        childAccount.Name = 'ChildAccount'; 
        insert childAccount;
        Set<Id> childAccountIds = new Set<Id>();
        childAccountIds.add(childAccount.Id);
        String serializedData = SObjectDataLoader.serialize(childAccountIds);
        Integer recordsBeforeDeletion = [Select count() from Account];
        List<Account> recordsToDelete =  new List<Account>();
        recordsToDelete.add(testParentAccount);
        recordsToDelete.add(childAccount);
        delete recordsToDelete;
        Integer recordsAfterDeletion = [Select count() from Account];
        system.assertEquals(recordsBeforeDeletion,recordsAfterDeletion+2);
        Set<Id> resultIds = SObjectDataLoader.deserialize(serializedData);
        List<Account> recordsAfterDeserialization =[Select Id,Name,ParentId from Account];
        system.assertEquals(recordsBeforeDeletion,recordsAfterDeserialization.size());
        Id parentRecordId;
        for(Account acc : recordsAfterDeserialization){
            if('childAccount'.equals(acc.Name)){
                parentRecordId = acc.ParentId;
                break;
            }
        }
        for(Account acc : recordsAfterDeserialization){
            if(parentRecordId!=null && acc.id ==parentRecordId){
                system.assertEquals(acc.Name,'ParentAccount');
                break;
            }
        }
    }
    
    @isTest(seeAllData=False)
    private static void deserializingObjectsWithSelfReferncesLevel2(){
        //add a ParentAccount
        Account testParentAccount = new Account(Name = 'ParentAccount');
        insert testParentAccount;
        
        //add a child to ParentAccount
        Account childAccount1 = new Account();
        childAccount1.ParentId =testParentAccount.Id;
        childAccount1.Name = 'ChildAccount1';   
        insert childAccount1;
        
        //add a child to childAccount1
        Account childAccount2 = new Account();
        childAccount2.ParentId =childAccount1.Id;
        childAccount2.Name = 'ChildAccount2';   
        insert childAccount2;

        //Create Bundle with childAccount2 as subcomponent
        Set<Id> childAccountIds = new Set<Id>();
        childAccountIds.add(childAccount2.Id);
        //Records are exported
        Map <Schema.SObjectType,SObjectDataLoader.SerializeConfig> strategyBySObjectType =
            new Map<Schema.SObjectType,SObjectDataLoader.SerializeConfig>();
        strategyBySObjectType.put(Account.SObjectType, new SObjectDataLoader.SerializeConfig()
            .follow(Account.RecordTypeId)
            .follow(Account.ParentId)
        );

        String serializedData = SObjectDataLoader.serialize(childAccountIds, strategyBySObjectType);
        
        Integer recordsBeforeDeletion = [Select count() from Account];
        List<Account> recordsToDelete =  new List<Account>();
        recordsToDelete.add(testParentAccount);
        recordsToDelete.add(childAccount1);
        recordsToDelete.add(childAccount2);
        delete recordsToDelete;
        
        Integer recordsAfterDeletion = [Select count() from Account];
        system.assertEquals(recordsBeforeDeletion,recordsAfterDeletion+3);
        
        //Importing Records
        Set<Id> resultIds = SObjectDataLoader.deserialize(serializedData);
        List<Account> recordsAfterDeserialization =[Select Id,Name,ParentId from Account];
        system.assertEquals(recordsBeforeDeletion,recordsAfterDeserialization.size());
        //Verify Parent child Relationship is maintained between Account Objects
        Account parentAcc = [select Id,Name from Account where Name like 'ParentAccount'];
        Account Child1Acc = [select Id,Name from Account where ParentId = :parentAcc.Id ];
        Account Child2Acc = [select Id,Name from Account where ParentId = :Child1Acc.Id ];
        //Account acc =[select a2.Id,a2.Name from Account a2 where a2.ParentId in (select a1.Id from Account a1 where a1.ParentId in (select a.Id from Account where a.Name like 'ParentAccount' ))];
        system.assertEquals(Child2Acc.Name,'ChildAccount2');
    }
    
    @isTest(seeAllData=False)
    private static void deserializingObjectsWithoutSelfRefernces(){
        List<Account> AccountList = new List<Account>();
        Account testAccount1 =  new Account(Name ='TestAccount1');
        Account testAccount2 =  new Account(Name ='TestAccount1');
        Account testAccount3 =  new Account(Name ='TestAccount1');
        
        AccountList.add(testAccount1);
        AccountList.add(testAccount2);
        AccountList.add(testAccount3);
        insert AccountList;
        
        //Create Bundle with Account Objects as subcomponent
        Set<Id> AccountIds = new Set<Id>();
        AccountIds.add(testAccount1.Id);
        AccountIds.add(testAccount2.Id);
        AccountIds.add(testAccount3.Id);
        //Records are exported
        String serializedData = SObjectDataLoader.serialize(AccountIds);
        
        Integer recordsBeforeDeletion = [Select count() from Account];
        List<Account> recordsToDelete =  new List<Account>();
        recordsToDelete.add(testAccount1);
        recordsToDelete.add(testAccount2);
        recordsToDelete.add(testAccount3);
        delete recordsToDelete;
        
        Integer recordsAfterDeletion = [Select count() from Account];
        system.assertEquals(recordsBeforeDeletion,recordsAfterDeletion+3);
        
        //Importing Records
        Set<Id> resultIds = SObjectDataLoader.deserialize(serializedData);
        List<Account> recordsAfterDeserialization =[select a.ParentId, a.Id from Account a where a.ParentId  =null];
        system.assertEquals(recordsBeforeDeletion,recordsAfterDeserialization.size());
    }   
    
     /*
    * Donot save an record subcomponent if error occurs
    */
     @isTest(seeAllData=False)
     private static void processUnorderedRecordsinJsonTest()
    {
        String testObjectJson = '{"RecordSetBundles":[{"Records":[{"attributes":{"type":"Contact","url":"/services/data/v29.0/sobjects/Contact/003b000000NStFRAA1"},'+
        '"IsEmailBounced":false,"CurrencyIsoCode":"USD","HasOptedOutOfFax":false,"LastModifiedDate":"2014-03-01T12:32:28.000+0000","HasOptedOutOfEmail":false,'+
        '"LastName":"MyContact","Name":"MyContact","DoNotCall":false,"AccountId":"001b000000P8LZgAAN","SystemModstamp":"2014-03-01T12:32:28.000+0000","CreatedDate":"2014-03-01T12:11:58.000+0000",'+
        '"IsDeleted":false,"Id":"003b000000NStFRAA1"}],"ObjectType":"Contact"},{"Records":[{"attributes":{"type":"Account","url":"/services/data/v29.0/sobjects/Account/001b000000P8LZgAAN"},'+
        '"Name":"ChildAccount","ParentId":"001b000000PBLqsAAH","CurrencyIsoCode":"USD","SystemModstamp":"2014-03-06T06:04:38.000+0000","CreatedDate":"2014-03-01T11:42:34.000+0000",'+
        '"LastModifiedDate":"2014-03-06T06:04:38.000+0000","IsDeleted":false,"Id":"001b000000P8LZgAAN"},{"attributes":{"type":"Account","url":"/services/data/v29.0/sobjects/Account/001b000000PBLqsAAH"},'+
        '"Name":"Parent Account","CurrencyIsoCode":"USD","SystemModstamp":"2014-03-06T06:04:15.000+0000","CreatedDate":"2014-03-06T06:04:15.000+0000","LastModifiedDate":"2014-03-06T06:04:15.000+0000",'+
        '"IsDeleted":false,"Id":"001b000000PBLqsAAH"}],"ObjectType":"Account"}]}';

        if(!UserInfo.IsMultiCurrencyOrganization())
        {
            testObjectJson = testObjectJson.remove('"CurrencyIsoCode":"USD",');
        }
        
        delete [Select Id from Account where Name = 'ChildAccount']; 
        delete [Select Id from Account where Name = 'Parent Account']; 
        delete [Select Id from Contact where Name = 'MyContact'];

        //Importing Records
        Set<Id> resultIds = SObjectDataLoader.deserialize(testObjectJson);
        List<Account> childAccountRecords = [select Id , ParentId from Account where Name like 'ChildAccount'];
        List<Account> parentAccountRecords = [select Id from Account where Name like 'Parent Account'];
        List<Contact> contactRecords = [select Id , AccountId from Contact where Name like 'MyContact'];
        
        system.assertEquals(childAccountRecords.size(), 1);
        system.assertEquals(parentAccountRecords.size(), 1);
        system.assertEquals(contactRecords.size(), 1);
        system.assertEquals(parentAccountRecords[0].Id, childAccountRecords[0].ParentId);
        system.assertEquals(childAccountRecords[0].Id,contactRecords[0].AccountId);
    }
    
    @isTest(seeAllData=False)
    private static void reportLimitExceptions()
    {
        Map<String, Schema.SObjectType> globalDescribeMap = Schema.getGlobalDescribe();
        Account accountObj = new Account(Name ='Account1');
        insert accountObj;
        List<Account> accList =[select Id from Account];
        for(Integer i=0;i<100;i++)
        {
            Schema.DescribeSObjectResult sObjectDesc = accList[0].Id.getSObjectType().getDescribe();
            Map<String, Schema.SObjectField> sObjectFields = sObjectDesc.fields.getMap();
        }
        String error ='';
        Set<Id> IdToSerialize = new Set<ID>();
        IdToSerialize.add(accountObj.Id);
        try
        {
            String serializedData = SObjectDataLoader.serialize(IdToSerialize);
        }
        catch(Exception e)
        {
            error = e.getMessage();
        }
        system.assert(String.isBlank(error));
    }
    
    @isTest(seeAllData=False)
    private static void userFieldBlackListTest()
    {
        Id idToSerialize;
        Map <Schema.SObjectType,SObjectDataLoader.SerializeConfig> strategyBySObjectType = new Map <Schema.SObjectType,SObjectDataLoader.SerializeConfig>();
        Map<String,List<String>> fieldBlackListMap = new Map<String,List<String>>();
        fieldBlackListMap.put('Account',new List<String>{'Site'});
        Map<String, Schema.SObjectType> globalDescribeMap = Schema.getGlobalDescribe();
        Schema.SObjectType accSObjectType = globalDescribeMap.get('Account');
        SObject acc = accSObjectType.newSObject();
        acc.put('Name', 'testAccount');
        acc.put('Site', 'testSite');
        insert acc;
        
        idToSerialize = acc.Id;
        Schema.SObjectType conSObjectType = globalDescribeMap.get('Contact');
        SObject con = conSObjectType.newSObject();
        con.put('LastName','testContact');
        if(UserInfo.IsMultiCurrencyOrganization())
        {
            con.put('CurrencyIsoCode','USD');
        }
        con.put('AccountId',acc.Id);
        insert con;
        
        Schema.SObjectType sObjectType = acc.Id.getSObjectType();
        if(strategyBySObjectType.get(sObjectType)==null)
        {
            SObjectDataLoader.SerializeConfig config = new SObjectDataLoader.SerializeConfig().addToUserFieldBlackList(fieldBlackListMap);
            strategyBySObjectType.put(sObjectType,config.auto(idToSerialize.getSObjectType()));
        }
        String jsonString = SObjectDataLoader.serialize(new Set<Id>{idToSerialize}, strategyBySObjectType);
        system.assert(!jsonString.contains('testSite'),jsonString);
        system.assert(jsonString.contains('Contact'),jsonString);
    }
    
    @isTest(seeAllData=False)
    private static void userFieldBlackListTestWithPackageBlaclist()
    {
        Id idToSerialize;
        Map <Schema.SObjectType,SObjectDataLoader.SerializeConfig> strategyBySObjectType = new Map <Schema.SObjectType,SObjectDataLoader.SerializeConfig>();
        Map<String,List<String>> fieldBlackListMap = new Map<String,List<String>>();
        fieldBlackListMap.put('Account',new List<String>{'Site'});
        Map<String, Schema.SObjectType> globalDescribeMap = Schema.getGlobalDescribe();
        Schema.SObjectType accSObjectType = globalDescribeMap.get('Account');
        SObject acc = accSObjectType.newSObject();
        acc.put('Name', 'testAccount');
        acc.put('Site', 'testSite');
        insert acc;
        
        idToSerialize = acc.Id;
        Schema.SObjectType conSObjectType = globalDescribeMap.get('Contact');
        SObject con = conSObjectType.newSObject();
        con.put('LastName','testContact');
        if(UserInfo.IsMultiCurrencyOrganization())
        {
            con.put('CurrencyIsoCode','USD');
        }
        con.put('AccountId',acc.Id);
        insert con;
        
        Set<String> packageNamespaceSet = new Set<String>{'abcd','pqrs'};
        Schema.SObjectType sObjectType = acc.Id.getSObjectType();
        if(strategyBySObjectType.get(sObjectType)==null)
        {
            SObjectDataLoader.SerializeConfig config = new SObjectDataLoader.SerializeConfig().addToBlacklistedNamespace(packageNamespaceSet).addToUserFieldBlackList(fieldBlackListMap);
            strategyBySObjectType.put(sObjectType,config.auto(idToSerialize.getSObjectType()));
        }
        String jsonString = SObjectDataLoader.serialize(new Set<Id>{idToSerialize}, strategyBySObjectType);
        system.assert(!jsonString.contains('testSite'),jsonString);
        system.assert(jsonString.contains('Contact'),jsonString);
    }

    /*
    * Test  omitting  fields common to all objects
    */
    
    @isTest(seeAllData=False)
    private static void testOmitCommonFields()
    {
        Id idToSerialize;
        Map <Schema.SObjectType,SObjectDataLoader.SerializeConfig> strategyBySObjectType = new Map <Schema.SObjectType,SObjectDataLoader.SerializeConfig>();
        Map<String,List<String>> childRelationshipBlackListMap = new Map<String,List<String>>();
        Map<String, Schema.SObjectType> globalDescribeMap = Schema.getGlobalDescribe();
        Schema.SObjectType accSObjectType = globalDescribeMap.get('Account');
        SObject acc = accSObjectType.newSObject();
        acc.put('Name', 'testAccount');
        acc.put('Site', 'testSite');
        insert acc;
        if(UserInfo.IsMultiCurrencyOrganization())
        {
            String serializedRecord = SObjectDataLoader.serialize(new Set<Id>{acc.Id}, new SObjectDataLoader.SerializeConfig().omitCommonFields(new Set<String>{'CurrencyIsoCode'}).auto(acc.Id.getSObjectType()));
            System.assert(!serializedRecord.contains('CurrencyIsoCode'));
        }
        else
        {
            String serializedRecord = SObjectDataLoader.serialize(new Set<Id>{acc.Id}, new SObjectDataLoader.SerializeConfig().auto(acc.Id.getSObjectType()));
            System.assert(!serializedRecord.contains('CurrencyIsoCode'));
        }
    }
    
    /*
    * Test  omitting  fields compound for Account Object
    */
    @isTest(seeAllData=False)
    private static void testOmitCompoundFieldsForAccount()
    {
        System.Savepoint savePoint = Database.setSavepoint();
        
        Id idToSerialize;
        Map <Schema.SObjectType,SObjectDataLoader.SerializeConfig> strategyBySObjectType = new Map <Schema.SObjectType,SObjectDataLoader.SerializeConfig>();
        Map<String,List<String>> childRelationshipBlackListMap = new Map<String,List<String>>();
        Map<String, Schema.SObjectType> globalDescribeMap = Schema.getGlobalDescribe();
        Schema.SObjectType accSObjectType = globalDescribeMap.get('Account');
        SObject acc = accSObjectType.newSObject();
        acc.put('Name', 'testAccount');
        acc.put('Site', 'testSite');
        // Using Shipping address instead of Billing, since CI process is failing due to orgs having salesforce's duplicate management features ON for this field.
        /*acc.put('BillingCity', 'abcCity');
        acc.put('BillingCountry', 'abcCountry');
        acc.put('BillingState', 'abcState');*/
        acc.put('ShippingCity', 'defCity');
        acc.put('ShippingCountry', 'defCountry');
        insert acc;
        String serializedRecord = SObjectDataLoader.serialize(new Set<Id>{acc.Id}, new SObjectDataLoader.SerializeConfig().auto(acc.Id.getSObjectType()));
        
        Database.rollback(savePoint);
        
        Set<Id> accIdSet = SObjectDataLoader.deserialize(serializedRecord);
        System.assertEquals(1, accIdSet.size());
        List<Account> accList = [select Name, BillingCity, BillingCountry, BillingState, BillingStreet, ShippingCity, ShippingCountry from Account where Id in :accIdSet];
        System.assertEquals(1,accList.size());
        System.assertEquals('defCity',accList[0].ShippingCity);
        System.assertEquals('defCountry',accList[0].ShippingCountry);
    }
    
     /*
    * Test  omitting  fields compound for Lead Object
    */
    @isTest(seeAllData=False)
    private static void testOmitCompoundFieldsForLead()
    {
        Id idToSerialize;
        Map <Schema.SObjectType,SObjectDataLoader.SerializeConfig> strategyBySObjectType = new Map <Schema.SObjectType,SObjectDataLoader.SerializeConfig>();
        Map<String,List<String>> childRelationshipBlackListMap = new Map<String,List<String>>();
        Map<String, Schema.SObjectType> globalDescribeMap = Schema.getGlobalDescribe();
        Schema.SObjectType leadSObjectType = globalDescribeMap.get('Lead');
        SObject testLead = leadSObjectType.newSObject();
        testLead.put('FirstName','test');
        testLead.put('LastName', 'Lead');
        testLead.put('Company', 'abc');
        testLead.put('LeadSource', 'lsrc');
        testLead.put('Street', 'abcStreet');
        testLead.put('City', 'abcCity');
        testLead.put('Country', 'abcCountry');
        testLead.put('State', 'abcState');
        testLead.put('PostalCode', '123456');
        // Org specific changes
        testLead.put('LeadSource', 'Internet');
        insert testLead;
        String serializedRecord = SObjectDataLoader.serialize(new Set<Id>{testLead.Id}, new SObjectDataLoader.SerializeConfig().auto(testLead.Id.getSObjectType()));
        Set<Id> leadIdSet = SObjectDataLoader.deserialize(serializedRecord);
        System.assertEquals(1, leadIdSet.size());
        List<Lead> leadList = [select LastName, FirstName, Company, LeadSource, Street, City, Country, State, PostalCode from Lead where Id in :leadIdSet];
        System.assertEquals(1,leadList.size());
        System.assertEquals('abcState',leadList[0].State);
        System.assertEquals('abcCountry',leadList[0].Country);
    }
    
     /*
    * Test  creating a map from json file  
    */
    @isTest(seeAllData=False)
    private static void testdeserializedRecords()
    {
        String accountRecordJsonFile ='{"RecordSetBundles":[{"Records":[{"attributes":{"type":"Account","url":"/services/data/v31.0/sobjects/Account/001b000000dPPN3AAO"},"Name":"TestAccount","SystemModstamp":"2014-09-29T05:06:08.000+0000","CreatedDate":"2014-09-29T05:06:08.000+0000","LastModifiedDate":"2014-09-29T05:06:08.000+0000","IsDeleted":false,"Id":"001b000000dPPN3AAO"}],"ObjectType":"Account"}]}';
        Map<String,List<Sobject>> recordBundleMap = new Map<String,List<Sobject>>();
        recordBundleMap = SObjectDataLoader.deserializedRecords(accountRecordJsonFile);
        System.assert(recordBundleMap.keyset().contains('Account'));
        List<Account> accList = (List<Account>)recordBundleMap.get('Account');
        System.assertEquals(accList[0].Name,'TestAccount');
    }
    
    @IsTest(seeAllData=true)
    public static void testManuallyConfigureMaxDepths()
    {   
        // Setup   
        Account grandParent = new Account(Name = 'Grand Parent');
        insert grandParent;
        Account parent = new Account(ParentId = grandParent.Id, Name = 'Parent');
        insert parent;
        Account child = new Account(ParentId = parent.Id, Name = 'Child');
        insert child;
        
        SObjectDataLoader.PreventInfinityLoopException expectedException = null;
        
        // Execute
        try {
            SObjectDataLoader.serialize(new Set<Id> {child.Id}, 
                                        new SObjectDataLoader.SerializeConfig()
                                                                    .maxLookupDepth(1)
                                                                    .maxChildDepth(1)
                                                                    .follow(Account.ParentId));
        }
        catch (SObjectDataLoader.PreventInfinityLoopException ex) {
            expectedException = ex;
        }
        
        //Verify
        System.assertNotEquals(null, expectedException);
    }
}