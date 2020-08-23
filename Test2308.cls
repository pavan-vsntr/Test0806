			 
/**
 * @description: This is the main class to enther the new contract.
 * @log
 * SK - 01/31/17 - BIZ - 10721
 * Modified for fixing bug with product selection.
 * <p>
 * FG - 08/22/2019 - ULTI-381048 
 * https://theskyplanner.quip.com/sgwWAdFqCpPi/ULTI-381048-Contract-Writeup-Record-Type
 * <p>
 * FG - 08/23/2019 - ULTI-381048 
 * https://theskyplanner.quip.com/e2nZAjhBaqOa/ULTI-383595-Breadcrumbs-Wizard-Updates
 */
public without sharing class EnterContractController 
		extends NavigationProviderBase
		implements AddressValidatorHandler {
	private Id opportunityId { get; set; }
	public Boolean bReadOnly { get; set; }
	public String contractType { get; set; }
	
	private RecordType closedRecordType;
	private RecordType enterpriserecordType;

	// Document page
	public ContentVersion file { get; set; }
	public Contract_Administration__c contractAdmin { get; set; }
	public Contract_Writeup__c contractWriteup { get; set; }
	public List<ContentVersion> insertedFiles { get; set; }
	public Integer selectedFileIndex { get; set; }
	
	private List<Id> ContentDocumentId;
	private Boolean fileNotSaved;
	private Boolean bDocumentAssociated;
	private List<Id> fileIds;	

	// account page
	public Boolean bCopyTolegalName { get; set; }
	public Boolean bCopyToShippingAddress { get; set; }
	public Account account { get; set; }
	public List<SelectOption> accountTypeOptions { get; set; }
	public Boolean isACA { get; set; }
	public Boolean isW2default { get; set; }

	private id prevAcctRT;
	private decimal acaValue;
	private decimal w2Value;

	// opportunity page
	public Opportunity opportunity { get; set; }
	public Boolean bPartnerSale { get; set; }
	public Boolean bOpportunitySplit { get; set; }
	public List<SelectOption> oppTypeOptions { get; set; }
		
	private Id prevOppRT;
	private map<Id, String> mpCDTitles;
	private Map<String, C360_Settings__c> c360settings;

	// products page
	public List<ProductSelectionWrapper> selectedProducts { get; set; }
	public List<ProductSelectionWrapper> availableProducts { get; set; }
	public String productIndexes { get; set; }
	public Map<Id, OpportunityLineItem> opportunityProductsMap { get; set; }
	public List<String> emptyNames { get; set; }
	private Map<String, String> productNameCodeMap;

	private Map<Id, OpportunityLineItem> productsToDelete;	
	private List<PricebookEntry> coreBundledProducts, printBundledProducts;
	private Set<String> doNotCopyEEForProds;
	private Set<Id> testProductIds;
	private Integer amountTestingProductsIndluded, 
		availableForCoreBundleCount, availableForPrintBundleCount;

	public Boolean includeTestProducts { get; set; }

	// submit page
	public Boolean bSubmitAllChanges { get; set; }
	public String submitText { get; set; }
	public Boolean bError { 
		get {
			return ApexPages.hasMessages();
		}
		set;
	}

	// curstep is public so we can set up the step# in test class
	public String contractTypeTemp { get; set; }
	private Boolean isNewContractAdmin = false;

	public Boolean isOpportunityClosed { get; private set; }
	public Boolean isPresales { get; private set; }
    public C360_Default_Values_Setting__mdt C360_Default_Values_Setting  { get; private set; }

	// location
	// Validation stages:
	// -1: n/a
	// 0: viewing
	// 1: editing
	// 2: validating
	// 3: saved
	private Integer addressValidationStage;

	/**
	 * Main constructor
	 */
	public EnterContractController() {
		String tempId = ApexPages.currentPage().getParameters().get('Id');
		
		if (!String.isBlank(tempId)) {
			try {
				opportunityId = (Id)tempId;
			} catch (Exception ex) {
				throw new NoAccessException(
					'Invalid opportunity ID. ' +
					'Make sure the Id pameter is the Id of ' +
					'an existing opportunity.');
			}

			file = new ContentVersion();
			ContentDocumentId = new List<id>();
			insertedFiles = new List<ContentVersion>();
			isOpportunityClosed = false;
			fileNotSaved = true;
			bDocumentAssociated = false;
			fileIds = new List<Id>();
			mpCDTitles = new map<Id, String>();
			
			bCopyTolegalName = false;
			bCopyToShippingAddress = false;
			bSubmitAllChanges = false;
			isACA = false;
			
			opportunityProductsMap = new Map<Id, OpportunityLineItem>();
			productsToDelete = new Map<Id, OpportunityLineItem>();

			coreBundledProducts = new List<PricebookEntry>();
			printBundledProducts = new List<PricebookEntry>();
			productNameCodeMap = new Map<String, String>();
			availableForCoreBundleCount = 0;
			availableForPrintBundleCount = 0;
			
			testProductIds = new Set<Id>();
			accountTypeOptions = new List<SelectOption>();
			oppTypeOptions= new List<SelectOption>();
			
			c360settings = C360_Settings__c.getAll();
			doNotCopyEEForProds = getNameSetFromSettings('Do_not_default_EEs__c');
			closedRecordType = USGRecordTypes.getRecordTypeByDeveloperName(
				'Opportunity_ClosedWonOpportunityRecordType');
			enterpriserecordType = USGRecordTypes.getRecordTypeByDeveloperName(
				'Opportunity_StandardSalesRecordType');

			loadAccountTypeOptions();
			loadOppTypeOptions();
			loadOpportunity();
			loadAccount();
			loadContractAdminAndWriteup();

			// load user info if there are split sales.
			loadUserInfoForSplitSalesPersons();
			// load products
			loadProducts();

			// user permissions
			isPresales = isPresale();

			// Read only conditions:
			bReadOnly =
				// 1. public String submitText { get; set; }
				(opportunity.RecordTypeId == closedRecordType.Id) ||
				// 2. if this a presales user, and the opportunity has 
				// already been close, we deny write permissions
				(OpportunityUtil.isClosedStage(opportunity.StageName) && isPresales);

			curstep = 1;
			setupSteps();
		} else
			throw new NoAccessException(
				'We need an opportunity to proceed. ' +
				'Make sure the Id pameter is set in the URL.');
	}

	/**
	 * @return true if the current user is part of the
	 * Pre-sales team (Permission set)
	 */
	private Boolean isPresale() {
		return [
			SELECT COUNT()
			FROM PermissionSetAssignment
			WHERE PermissionSet.Name = 'C360_Pre_Sales_Access'
			AND AssigneeId = :UserInfo.getUserId()
		] > 0;
	}

	/**
	 * @return the current instance of this controller
	 */
	public EnterContractController getCurrentInstance() {
		return this;
	}

	public Boolean isThisNonCoreContract {
		get {
			return contractType == ContractWriteUpUtil.CONTRACT_TYPE_NONCORE;
		}
	}

	public Boolean isThisSAASNewContract {
		get {
			return contractType == ContractWriteUpUtil.CONTRACT_TYPE_SAAS_NEW_BUSINESS;
		}
	}

	public Boolean isAdditionalBusiness {
		get {
			return 
				contractType == 
					ContractWriteUpUtil.CONTRACT_TYPE_ADDITIONAL_BUSINESS ||
				contractType ==
					ContractWriteUpUtil.CONTRACT_TYPE_AMENDMENT_ADDTN_BUSINESS;
		}
	}

	public Boolean isThisAProspectAccount {
		get {
			return account.recordtypeid ==
				AccountUtil.AccountRecordTypeMap.get('ProspectRecordType').Id;
		}
	}

	private void loadAccountTypeOptions() {
		Schema.DescribeFieldResult accountType = Schema.sObjectType.Account.fields.Type;
		List<Schema.PicklistEntry> accountTypeValues = accountType.getPicklistValues();

		for (Schema.PicklistEntry a : accountTypeValues)
			if (a.getLabel() != 'Customer - Workplace')
				accountTypeOptions.add(
					new SelectOption(a.getLabel(), a.getValue()));
		
		accountTypeOptions.sort();
	}

	private void loadOppTypeOptions() {
		for (Schema.PicklistEntry a :
				Schema.sObjectType.Opportunity.fields.Type.getPicklistValues())
			oppTypeOptions.add(new SelectOption(a.getLabel(), a.getValue()));
	}

	private void loadAccount() {
		OpportunityContactRole ocr;

		// load account
		account = [
			SELECT Id,
				Method_of_Payment__c,
				Legal_Name__c,
				Name,
				Type,
				Phone,
				Fax,
				RecordTypeId,
				UltiPro_Processing_Type__c,
				AR_Status__c,
				AR__c,
				Billing_Type__c,
				Comments__c,
				Company_Code__c,
				Shipping_Contact_Title__c,
				Registration_Key_Email__c,
				Shipping_Contact__c,
				Group_Code__c,
				Escrow_Agent__c,
				Escrow_Agreement_Date__c,
				Business_Associate_Agreement_Date__c,
				Customer_As_Of__c,
				Legal_State_Province_of_Incorporation__c
			FROM Account
			WHERE Id = :opportunity.accountId
		];

		prevAcctRT = account.RecordTypeId;
		account.UltiPro_Processing_Type__c = 'Saas';
		account.AR_Status__c = account.AR_Status__c == null ?
			'Good' : account.AR_Status__c;
		account.Legal_Name__c = account.Legal_Name__c == null ?
			'' : account.Legal_Name__c;

		if (account.Shipping_Contact__c == null) {
			try {
				ocr = [
					SELECT ContactId,
						Id,
						OpportunityId,
						IsPrimary,
						Role,
						Contact.Title,
						Contact.Email
					FROM OpportunityContactRole
					WHERE OpportunityId = :opportunityId 
					AND IsPrimary = true
				];
			} catch (Exception ex) {
				system.debug ('There is no contact role on this opportunity');
			}

			if (ocr != null) {
				account.Shipping_Contact__c = ocr.ContactId;
				account.Shipping_Contact_Title__c = ocr.Contact.Title;
				account.Registration_Key_Email__c = ocr.Contact.Email;
			}
		}
	}

	/**
	 * Fetch and sets up inital informationa about the 
	 * existing opportunity.
	 */
	private void loadOpportunity() {
		// load opportunity
		opportunity = [
			SELECT Id,
				AccountId,
				Amount,
				Type,
				Ownerid,
				StageName,
				Is_Name_Defaulted__c, 
				Name, 
				Contract_Administration__c,
				Description,
				RecordTypeId,
				Book_Month__c,
				Book_Year__c,
				Split__c,
				Account.type,
				Account.Name,
				Account.Group_Code__c,
				split_salesperson__c,
				Split_Salesperson_2__c,
				Spilt__c,
				Split_Salesperson_percent__c,
				Split_Salesperson_1__c, 
				Split_Salespersons_2__c,
				Split_Salesperson_1_Manager__c,
				Spilt_Salesperson_Divison__c,
				Split_Salesperson_1_Unit__c,
				Spilt_Salesperson_2_Divison__c,
				Split_Salesperson_2_Manager__c,
				Split_Salesforce_2_Unit__c,
				Do_Not_Deduct_From_SQC__c,
				SQC_Amount__c,
				Total_SQC__c,
				Division_Region__c,
				Primary_Salesperson_Unit__c,
				Contracted_Number_of_Employees__c,
				Referral__c,
				Referral_Notes__c,
				Referral_Partner__c,
				ERM_Account_Band_1__c,
				ERM_Account_Band_2__c,
				Pricer_Effective_Date__c
			FROM Opportunity 
			WHERE Id = :opportunityId
		];

		// we keep account if the opp is closed
		isOpportunityClosed = OpportunityUtil.isClosedStage(opportunity);

		if (opportunity.SQC_Amount__c == null)
			opportunity.SQC_Amount__c = opportunity.Total_SQC__c;
		
		prevOppRT = opportunity.RecordTypeId;

		// load split flag.
		bOpportunitySplit = (opportunity.Split__c == 'Yes');
	}

	private void defaultOpportunityName() {
		String Name = null;

		if (bReadOnly || opportunity.Is_Name_Defaulted__c == true)
			return;

		if (isThisSAASNewContract) {
			if (contractadmin.Amended_And_Restated__c)
				Name = opportunity.Account.Name + 
					' - Amended and Restated SaaS Agreement';
			else 
				Name = opportunity.Account.Name + ' - SaaS Agreement';
		} else if (isThisNonCoreContract || IsAdditionalBusiness)
			Name = opportunity.Account.Name;

		if (Name != null) {
			opportunity.Is_Name_Defaulted__c = true;
			opportunity.Name = Name.left(120);
		}
	}

	private Boolean isEnterprise() {
		String aType = (account == null) ?
			opportunity.Account.Type : account.Type;

		// if closed won and group code is A or opportunity record type is enterprise
		return (aType == 'Customer - Enterprise' ||
			opportunity.Account.Group_Code__c == 'B' ||
			opportunity.recordtypeid==enterpriserecordType.Id);
	}

	private void loadUserInfoForSplitSalesPersons(){
		Set<Id> userIds = new Set<Id>();
		Map<Id, User> userMap;

		if (opportunity.ownerId != null)
			userIds.add(opportunity.ownerId);

		if (opportunity.split_salesperson__c != null)
			userIds.add(opportunity.split_salesperson__c);

		if (opportunity.Split_Salesperson_2__c != null)
			userIds.add(opportunity.Split_Salesperson_2__c);

		if (userIds.size()>0) {
			userMap = getUserInfo(userIds);
			setUserInfoForOppOwner(userMap.get(opportunity.ownerId));
			setUserInfoForSplit1(userMap.get(opportunity.split_salesperson__c));
			setUserInfoForSplit2(userMap.get(opportunity.Split_Salesperson_2__c));
		}
	}

	/**
	 * Leads or create conrtact admin and contract writeup
	 */
	private void loadContractAdminAndWriteup() {
		// load contract admin record if exists otherwise create a new one.
		if (opportunity.Contract_Administration__c !=null) {
			contractAdmin = [
				SELECT Account__c,
					Contract_Effective_Date__c,
					Contract_Type__c,
					Date_Signed_By_Ultimate__c,
					Total_Contract_EEs__c,
					Termination_Right_Date__c,
					Document_Link__c,
					Contract_Reference__c,
					Report_Administrator_s__c,
					Cog8_Consumer__c,
					Security_Administrator_s__c,
					Portal_Adminstrator_s__c,
					Cog8_Unlimited_Consumer__c,
					Cog8_Author__c,
					User_Calculation_per_1000__c,
					Concurrent_Users__c,
					Unlimited_Concurrent_Users__c,
					Implementation_Initial_Rate_Per_Hour__c,
					SLO_Uptime__c,
					Int_Environment__c,
					Milestone_Event__c,
					Other_Contract_Term_Start_Date__c,
					Subscription_Fee_Increase__c,
					Initial_Contract_Term__c,
					Subscription_Fee_Term_Prior_to_Incr__c,
					Inital_Term__c,
					Early_Termination_Time_Frame__c,
					After_Hours_Support_Billing_Rate__c,
					Termination_Right_During_Initial_Term__c,
					After_Hours_Support_No_Charge__c,
					SSO__c,
					Implementation_2nd_Rate_Per_Hour__c,
					SSO_O_T_Fee__c,
					W2_Rate__c,
					ACA_Print_Rate__c,
					No_Specified_W2_Rate_Grid__c,
					Testing_Services_Agreement__c,
					Testing_Services__c,
					Additonal_Refreshes__c,
					Testing_Services_Flat_Fee__c,
					Cost_per_Additional_Refresh__c,
					Migration_Fee__c,
					Amended_And_Restated__c,
					Signature_Not_Required__c,
					Content_Distribution_Id__c,
					IsTestingProductsCheckbox__c,
					Document_Links__c,
					Expedited_Fee__c,
					Handling_Fee__c,
					Handling_Rate__c,
					Split_Fee__c,
					Misc_Adjustment_Other_SQC_Adj__c,
					Custom_Launch_Quote__c,
					Launch_Fee_Adjustment__c,
					Launch_Pricer_Adjustment__c,
					Subscription_Pricer_Adjustment__c,
					Book_Month__c,
					Free_Splits__c,
					Standard_Activation__c,
					Is_3rd_Party_Launch__c,
					Launch_Period_Mo_s__c,
					Launch_Services_Expire_mo_s__c,
					HR360_Users__c,
					HR360_Additional_User_Rate__c
				FROM Contract_Administration__c
				WHERE Id = :opportunity.Contract_Administration__c
			];

			acaValue = contractAdmin.ACA_Print_Rate__c;
			w2Value = contractAdmin.W2_Rate__c;

			// BIZ-9063 Prevent Testing Services Checkbox From 
			// Reverting When Saved in PSA Wizard
			includeTestProducts = contractAdmin.IsTestingProductsCheckbox__c;

			// ULTI-383104
			// contract writeup must exist from the beginning
			// we need the contract writeup
			contractWriteup = ContractWriteUpUtil.getWriteUpRecord(opportunity.Id);
			// if no contract writeup, we create a new one
			if (contractWriteup == null)
				contractWriteup = ContractWriteUpUtil.createWriteUpRecord(
					opportunity, contractAdmin, 'Pending Draft');
		} else {			
																											   
			contractAdmin = new Contract_Administration__c();
			contractAdmin.Opportunity_Name2__c = opportunity.Id;
			contractAdmin.Contract_Type__c = contractType;
			contractAdmin.After_Hours_Support_No_Charge__c = true;
			contractAdmin.Account__c = opportunity.AccountId;
			contractAdmin.Total_Contract_EEs__c =
				opportunity.Contracted_Number_of_Employees__c;
			includeTestProducts = false;

			// BIZ-9375. set comments field to null by default. C360:
			// Prevent Opportunity Description from Populating 
			// Comments Field of New Contract Wizard
			opportunity.Description = null;
			isNewContractAdmin = true;

			// ULTI-383104
			// contract writeup must exist from the beginning
			contractWriteup = ContractWriteUpUtil.createWriteUpRecord(
					opportunity, contractType);
		}
C360_Default_Values_Setting = ContractAdministrationUtil.InitializeDefaultValues();	
		contractType = contractAdmin.Contract_Type__c;
	}

	/**
	 * @param isNewACA
	 */
	private void setContractAdminRates(Boolean isNewACA) {
		if (isACAdefault(account, isNewACA, contractAdmin)) {
			if (contractAdmin.ACA_Print_Rate__c == null && !isACA && acaValue == null) {
				contractAdmin.ACA_Print_Rate__c = 
					C360settings.get('Default').ACA_Print_Rate__c;
				isACA = true;
			} else if (contractAdmin.ACA_Print_Rate__c == 2)
				isACA = true;
		} else {
			if (contractAdmin.ACA_Print_Rate__c == 2.00 && acaValue == null && !isNewACA)
				contractAdmin.ACA_Print_Rate__c = null;

			if (acaValue != null && contractAdmin.ACA_print_Rate__c == null)
				contractAdmin.ACA_Print_Rate__c = acaValue;
			
			isACA = false;
		}

		if (isW2defaultValue() && contractAdmin.w2_rate__c == null) {
			contractAdmin.w2_rate__c = c360settings.get('Default').W2_Rate__c;
			isW2default = true;
		} else if (contractAdmin.Id == null)
			isW2default = false;
		else
			contractAdmin.w2_rate__c = w2Value;
	}

	/**
	 * Loads the products: selected, available, bundled, prints, tests, etc.
	 * This method sets up the products for the application. 
	 * CALL ONCE ON INITIALIZATION.
	 */
	private void loadProducts() {
		Boolean isCore, isPrint, isAvailableToSaas,
			isAvailableForCoreBundle, isAvailableForPrintBundle, isVisible,isTimeclock;
		Map<Id, OpportunityLineItem> existingOlis;
		Map<Id, PricebookEntry> priceBookEntries;
		ProductSelectionWrapper wrapper;
		Set<String> coreBundles, printDefaults, printBundledProductNames;
		OpportunityLineItem existentOli;

		
		// product related to bundles
		coreBundles = getNameSetFromSettings('Core_Bundled_Products__c');
		printDefaults = getNameSetFromSettings('Print_Services_Default_Product__c');
		printBundledProductNames = 
			getNameSetFromSettings('Print_Services_Bundled_Products__c');

		// loop through existing opportunity products to initialize
		// opportunity products map and setting up selected product list box values
		existingOlis = new Map<Id, OpportunityLineItem>();
		for (OpportunityLineItem oli : getExistentOpportunityProducts())
			existingOlis.put(oli.PricebookEntryId, oli);
				
		// For Non core contract , 
		// we load only stand alone products 
		// (Stand alone product without ulti pro)
		priceBookEntries = getProducts(existingOlis.keySet());

		selectedProducts = new List<ProductSelectionWrapper>();
		availableProducts = new List<ProductSelectionWrapper>();

		// if a product already exists on an opportunity the value of selectio option
		// will include the opportunity product id also. otherwise just the 
		// product Id and pricebook entry id;
		for (PricebookEntry pbe : priceBookEntries.values()) {
   
			// if this i a type product add it to the type product map
			// (e.g. trminated web employee product)
			isAvailableForCoreBundle = coreBundles.contains(pbe.product2.Name);
			if (isAvailableForCoreBundle)
				coreBundledProducts.add(pbe);
			
			// print products will bring bundles with them
			isAvailableForPrintBundle = printDefaults.contains(pbe.Product2.Name);
			if (isAvailableForPrintBundle)
				printBundledProducts.add(pbe);
						
			// if it is a testing product add it to test product id collection.
			if (pbe.Product2.Is_Test_Product__c)
				testProductIds.add(pbe.Product2Id);

			// create a list of selected products and available products from 
			// the list of all active pricebook enries for Ultimate pricebook.
			// neelimab-11/9/2015 updated isCore logic for additional products
			isCore = false;
			if (!pbe.product2.Name.contains('Additional'))
				isCore = (pbe.Product2.Is_Core__c == null) ? 
					false : pbe.Product2.Is_Core__c;

			// core - prints
			isPrint = printBundledProductNames.contains(pbe.Product2.Name);

			// to be vailable to SaaS, field need to have a value,
			// and this value must be true
			isAvailableToSaas = 
				pbe.Product2.Is_available_to_SaaS_Contracts__c != null &&
				pbe.Product2.Is_available_to_SaaS_Contracts__c;
			productNameCodeMap.put(pbe.Product2.Name, pbe.ProductCode);

 

			// product might be hidden
			isVisible = isOpportunityClosed || isAvailableToSaas;
   
			//Timeclock products should be hidden in the wizard
			isTimeclock = pbe.ProductCode=='CLK'||pbe.ProductCode=='SCLK';
			if (isTimeclock) {isVisible = false;}										  
 

										  

			if (existingOlis.containskey(pbe.id)) {
				existentOli = existingOlis.get(pbe.id);
				// get the opportunity line item id for an existing pricebook entry
				wrapper = new ProductSelectionWrapper(pbe, existentOli, 
					isCore, isPrint, pbe.Product2.Is_Test_Product__c,
					isAvailableForCoreBundle, isAvailableForPrintBundle,
					existentOli.Is_Core_Bundled__c, existentOli.Is_Print_Bundled__c,
					isVisible);

				// set iscore to false if it is a null 
				// (in case the product is set up incorrectly)
				selectedProducts.add(wrapper);
				addOpportunityProduct(wrapper);
			}
			// ULTI-397614 - SaaS Contract Products for Wizard
			// 1. If the opportunity has not been closed, we only
			// include products that have been flagged as 
			// "Is available to SaaS Contracts"...
			// 2. If the opportunity is closed already, all products qualify 
			// as available.
			else if (isVisible)
				availableProducts.add(
					new ProductSelectionWrapper(pbe, null, 
						isCore, isPrint, pbe.Product2.Is_Test_Product__c,
						isAvailableForCoreBundle, isAvailableForPrintBundle, 
						false, false, true));
			
			if (isVisible) {
				// we add to count if available for core bundle
				if (isAvailableForPrintBundle)
					availableForCoreBundleCount++;
				// we add to count if available for print bundle
				if (isAvailableForPrintBundle)
					availableForPrintBundleCount++;
			}
		}
	}

	/**
	 * @return products that can be selected, might be already selected
	 * in this tool. 
	 * @param existentPricebookEntryIds
	 */
	private Map<Id, PricebookEntry> getProducts(Set<Id> existentPricebookEntryIds) { 
		return new Map<Id, PricebookEntry>(
			(List<PricebookEntry>)
			Database.query(
				'SELECT Name, ' +
					'IsActive, ' +
					'ProductCode, ' +
					'Product2Id, ' +
					'Product2.Name, ' +
					'Pricebook2Id, ' +
					'Pricebook2.Name, ' +
					'Product2.Is_Core__c, ' +
					'Product2.Is_Print_Service__c, ' +
					'Product2.Is_Test_Product__c, ' +
					'Product2.Is_available_to_SaaS_Contracts__c, ' +
					'Product2.Test_Environment__c ' +
				'FROM PricebookEntry ' +
				(Test.isRunningTest() ?
					// test runs
					'WHERE Pricebook2Id = \'' + Test.getStandardPricebookId() + '\' ' :
					// actual run
					'WHERE Pricebook2.Name = \'ultimate price book\' ' +
					// extra filter if non contract
					(isThisNonCoreContract ?
						'AND Product2.Applies_to_Standalone_Product__c = TRUE ' : '') +
					'AND ( ' +
						'IsActive = true ' +
						'OR Id IN :existentPricebookEntryIds ' +
					') '
				) +
				'ORDER BY Name'
			)); 
	}

	private Boolean isACAFileOnly(String name) {
		return name == 'ACA Management Services (File only)' ||
			name == 'ACA Distribution Services (File only)';
	}

	/**
	 * @param fieldName
	 * @return A set of names in the setting fields, which are expected
	 * to be separated by a ';'.
	 */
	private Set<String> getNameSetFromSettings(String fieldName) {
		C360_Settings__c c360DefaultSetting;
		Object fieldValue;
		Set<String> result;

		c360DefaultSetting = c360Settings.get('Default');
		fieldValue = c360DefaultSetting.get(fieldName);
		result = new Set<String>();

		if (fieldValue != null)
			for (String nm : String.valueOf(fieldValue).split(';'))
				result.add(nm);

		return result;
	}

	/**
	 * Moves a product option from available to selected
	 */
	public void addProducts() {
		List<ProductSelectionWrapper> added;
		Boolean addCores = false,
			addPrints = false,
			isNewACA = false,
			addTestingServices = false;
		String nm;

		added = transferProducts(availableProducts, selectedProducts, false);
		for (ProductSelectionWrapper wrapper : added) {
			nm = wrapper.priceBookEntry.Product2.Name;
			addOpportunityProduct(wrapper);

			if (wrapper.isCore)
				addCores = true;
			
			if (wrapper.isPrint)
				addPrints = true;
			
			if (productNameCodeMap.get(nm) == 'ACA' && 
					isACAFileOnly(nm) && wrapper.oppLineItem.Id == null)
				isNewACA = true;
			
			if (String.isNotBlank(wrapper.priceBookEntry.Product2.Test_Environment__c))
				addTestingServices = true;
		}

		// since one core product was added,
		// we need to add the bundles
		if (addCores)
			addCoreBundledDependantProducts();
		
		// since one print product was added,
		// we need to add the bundles
		if (addPrints)
			addPrintBundledDependantProducts();

		// 
		setContractAdminRates(isNewACA);

		// and we might need to add testing services
		if (addTestingServices)
			addTestingProductsIfCheckBoxSelected();
	}

	/**
	 * Moves a product option from selected to available
	 */
	public void removeProducts() {
		List<ProductSelectionWrapper> removed;
		Boolean removeCores = false,
			removePrints = false;

		removed = transferProducts(selectedProducts, availableProducts, true);
		for (ProductSelectionWrapper wrapper : removed) {
			removeOpportunityProduct(wrapper);

			if (wrapper.isCore)
				removeCores = true;
			
			if (wrapper.isPrint)
				removePrints = true;
		}

		// if a core was removed, we might need to remove the bundles
		if (removeCores)
			removeCoreBundledDependantProducts();

		if (removePrints)
			removePrintBundledDependantProducts();
	}

	/**
	 * Set the opportunity product records based on the 
	 * selected produts in the products page. Some of these 
	 * products might be existing
	 * @param psw
	 */
	private void addOpportunityProduct(ProductSelectionWrapper psw) {
		// if the opportunity product has not bee created,
		// we create it...
		if (psw.oppLineItem == null)
			psw.oppLineItem = new OpportunityLineItem(
				OpportunityId = opportunity.Id,
				PricebookEntryId = psw.pricebookEntry.Id,
				OT_Fee__c = false,
				Subscription_Fee__c = 
					(psw.pricebookEntry.Product2.Is_Print_Service__c == null &&
						psw.pricebookEntry.Product2.Is_Print_Service__c) || 
					(psw.isCore && !psw.isTest),
				Active_Employees__c = getInitialActiveEmployees(
					psw.priceBookEntry.Product2.Name)
			);
		
		psw.oppLineItem.Is_Core_Bundled__c = psw.isCoreBundle;
		psw.oppLineItem.Is_Print_Bundled__c = psw.isPrintBundle;

		if (!opportunityProductsMap.containsKey(psw.pricebookEntry.Id))
			opportunityProductsMap.put(psw.pricebookEntry.Id, psw.oppLineItem);

		if (psw.oppLineItem.Book_Month__c != opportunity.Book_Month__c)
			psw.oppLineItem.Book_Month__c = opportunity.Book_Month__c;

		if (psw.oppLineItem.Book_Year__c != opportunity.Book_Year__c)
			psw.oppLineItem.Book_Year__c = opportunity.Book_Year__c;
		
		// if this product was marked for deletion before,
		// we remove this mark...
		if (productsToDelete.containsKey(psw.pricebookEntry.Id))
			productsToDelete.remove(psw.pricebookEntry.Id);
	}

	/**
	 * Based on a core product, adds all bundle-dependant products
	 * if have not been added already.
	 * @param wwrapper
	 */
	private void addCoreBundledDependantProducts() {
		Integer index;
		List<String> addedIndexes;
		ProductSelectionWrapper wrapper;
		List<ProductSelectionWrapper> added;

		index = 0;
		addedIndexes = new List<String>();

		// first, we try to find bundle products in the 
		// available products list...
		if (availableForCoreBundleCount > 0) {
			for (ProductSelectionWrapper psw : availableProducts) {
				if (psw.isAvailableForCoreBundle) {
					psw.isCoreBundle = true;
					addedIndexes.add(String.valueOf(index));
				}
				index++;
			}

			// if we added any from the list, we add them now...
			if (!addedIndexes.isEmpty()) {
				productIndexes = String.join(addedIndexes, ',');
				added = transferProducts(availableProducts, selectedProducts, false);
				// we add them all
				for (ProductSelectionWrapper psw : added)
					addOpportunityProduct(psw);
			}
		}

		// now we go to the conceptual bundle product to check if 
		// if anyone is missing
		for (PricebookEntry pbe : coreBundledProducts)
			// if the bundled product has already been added
			// we don't need to do anything... we only take action if the
			// bundled dependant product is new..
			if (!opportunityProductsMap.containsKey(pbe.Id)) {
				// get the opportunity line item id for an existing pricebook entry
				wrapper = new ProductSelectionWrapper(pbe, null, 
					false, false, pbe.Product2.Is_Test_Product__c, 
					true, false, true, false, false);
				// and we add to the opp products and selected products
				addOpportunityProduct(wrapper);
				selectedProducts.add(wrapper);
			}
	}

	/**
	 * Based on a print product, adds all bundle-dependant products
	 * if any of them have not been added already.
	 * @param wwrapper
	 */
	private void addPrintBundledDependantProducts() {
		Integer index;
		List<String> addedIndexes;
		ProductSelectionWrapper wrapper;
		List<ProductSelectionWrapper> added;

		index = 0;
		addedIndexes = new List<String>();

		// first, we try to find bundle products in the 
		// available products list...
		if (availableForPrintBundleCount > 0) {
			for (ProductSelectionWrapper psw : availableProducts) {
				if (psw.isAvailableForPrintBundle) {
					psw.isPrintBundle = true;
					addedIndexes.add(String.valueOf(index));
				}
				index++;
			}

			// if we added any from the list, we add them now...
			if (!addedIndexes.isEmpty()) {
				productIndexes = String.join(addedIndexes, ',');
				added = transferProducts(availableProducts, selectedProducts, false);
				// we add them all
				for (ProductSelectionWrapper psw : added)
					addOpportunityProduct(psw);
			}
		}

		for (PricebookEntry pbe : printBundledProducts)
			// if the bundled product has already been added
			// we don't need to do nothing... we only take action if the
			// bundled dependant product is new..
			if (!opportunityProductsMap.containsKey(pbe.Id)) {
				// get the opportunity line item id for an existing pricebook entry
				wrapper = new ProductSelectionWrapper(pbe, null, 
					false, false, pbe.Product2.Is_Test_Product__c,
					false, true, false, true, false);
				// and we add to the opp products and selected products
				addOpportunityProduct(wrapper);
				selectedProducts.add(wrapper);
			}
	}

	/**
	 * If there are no more core products selected,
	 * this method remove the bundle dependant products.
	 */
	private void removeCoreBundledDependantProducts() {
		Boolean isStillCore;
		List<ProductSelectionWrapper> toRemove;
		List<Integer> indexesToRemove, indexesToDiscard;
		Integer index;

		// initially, we assume there no more cores
		isStillCore = false;

		// first, lest find out if there is still a core
		for (ProductSelectionWrapper wrapper : selectedProducts)
			// if not, if its Core, we keep it in mind
			if (wrapper.isCore) {
				isStillCore = true;
				break;
			}

		// if there is still a core, we do nothign else
		// and leave all bundles there... we proceed if there is no core
		if (!isStillCore) {
			if (availableForCoreBundleCount > 0) {
				index = 0;
				indexesToDiscard = new List<Integer>();

				// we need to remove not visible products first
				for (ProductSelectionWrapper wrapper : selectedProducts) {
					// if product is not visible, we remove it right away
					// without moving it into the vailable list,
					// and we don't advance the counter
					if (wrapper.isCoreBundle && !wrapper.isVisible)
						indexesToDiscard.add(index);
					index++;
				}

				// we now discard the ones found before
				if (!indexesToDiscard.isEmpty())
					for (Integer i = indexesToDiscard.size() - 1; i >= 0; i--)
						removeOpportunityProduct(
							selectedProducts.remove(indexesToDiscard[i]));
			}

			// if we have products left, we move to delete those that were
			// bundled but ae visible
			if (!selectedProducts.isEmpty()) {
				indexesToRemove = new List<Integer>();
				index = 0;

				for (ProductSelectionWrapper wrapper : selectedProducts) {
					if (wrapper.isCoreBundle)
						indexesToRemove.add(index);
					index++;
				}
				
				// if there are no more cores
				if (!indexesToRemove.isEmpty()) {
					productIndexes = String.join(indexesToRemove, ',');
					removeProducts();
				}
			}
		}
	}

	/**
	 * If there are no more core products selected,
	 * this method remove the bundle dependant products.
	 */
	private void removePrintBundledDependantProducts() {
		Boolean isStillPrint;
		List<ProductSelectionWrapper> toRemove;
		List<Integer> indexesToRemove, indexesToDiscard;
		Integer index;

		// initially, we assume there no more Prints
		isStillPrint = false;

		// first, lest find out if there is still a Print
		for (ProductSelectionWrapper wrapper : selectedProducts)
			// if not, if its Print, we keep it in mind
			if (wrapper.isPrint) {
				isStillPrint = true;
				break;
			}

		// if there is still a Print, we do nothign else
		// and leave all bundles there... we proceed if there is no Print
		if (!isStillPrint) {
			if (availableForPrintBundleCount > 0) {
				index = 0;
				indexesToDiscard = new List<Integer>();

				// we need to remove not visible products first
				for (ProductSelectionWrapper wrapper : selectedProducts) {
					// if product is not visible, we remove it right away
					// without moving it into the vailable list,
					// and we don't advance the counter
					if (wrapper.isPrintBundle && !wrapper.isVisible)
						indexesToDiscard.add(index);
					index++;
				}
				
				// we now discard the ones found before
				if (!indexesToDiscard.isEmpty())
					for (Integer i = indexesToDiscard.size() - 1; i >= 0; i--)
						removeOpportunityProduct(
							selectedProducts.remove(indexesToDiscard[i]));
			}

			// if we have products left, we move to delete those that were
			// bundled but ae visible
			if (!selectedProducts.isEmpty()) {
				indexesToRemove = new List<Integer>();
				index = 0;

				for (ProductSelectionWrapper wrapper : selectedProducts) {
					if (wrapper.isPrintBundle)
						indexesToRemove.add(index);
					index++;
				}
				
				// if there are no more Prints
				if (!indexesToRemove.isEmpty()) {
					productIndexes = String.join(indexesToRemove, ',');
					removeProducts();
				}
			}
		}
	}

	/**
	 * Remove the current product from the lists, and marks it for deletion.
	 * @param psw
	 */
	private void removeOpportunityProduct(ProductSelectionWrapper psw) {
		// we have to remove the bundle tags
		// as this wrapper is not a bundle anymore
		psw.isCoreBundle = false;
		psw.oppLineItem.Is_Core_Bundled__c = false;
		psw.isPrintBundle = false;
		psw.oppLineItem.Is_Print_Bundled__c = false;

		// we remove the product from the map
		opportunityProductsMap.remove(psw.pricebookEntry.Id);

		// we mark the current product for deletion, 
		// if it is an existent product
		if (!String.isBlank(psw.oppLineItem.Id))
			productsToDelete.put(psw.pricebookEntry.Id, psw.oppLineItem);
	}

	/**
	 * @param fromList
	 * @param toList
	 * @param sortDestination
	 */
	private List<ProductSelectionWrapper> transferProducts(
			List<ProductSelectionWrapper> fromList,
			List<ProductSelectionWrapper> toList, 
			Boolean sortDestination) {
		Integer index;
		ProductSelectionWrapper adding;
		List<ProductSelectionWrapper> touched;
		List<Integer> toRemove;
		
		toRemove = new List<Integer>();
		touched = new List<ProductSelectionWrapper>();
		for (String iStr : productIndexes.split(',')) {
			index = Integer.valueOf(iStr);
			adding = fromList[index];
			toList.add(adding);
			touched.add(adding);
			toRemove.add(index);
		}

		if (sortDestination)
			toList.sort();

		toRemove.sort();
		for (Integer i = toRemove.size() - 1; i >= 0; i--)
			fromList.remove(toRemove[i]);
		
		return touched;
	}

	/**
	 * @param acc
	 * @param isprodcodeACA
	 * @param contractAdmin
	 */
	private Boolean isACAdefault(Account acc, Boolean isprodcodeACA, 
			Contract_Administration__c contractAdmin) {
		return (isAccountEligibleForACA(acc) && isprodcodeACA) &&
			(IsAdditionalBusiness || 
				(isThisSAASNewContract && 
				contractAdmin.ACA_print_Rate__c == null));
	}

	private Boolean isAccountEligibleForACA(Account acc){
		return (acc.Type == 'Customer - BSP' ||
			acc.Type == 'Customer - Enterprise' ||
			acc.Type == 'Customer - PEO');
	}

	private Boolean isW2defaultValue() {
		return (account.Type == 'Customer - BSP' ||
			account.Type == 'Customer - Enterprise' ||
			account.Type == 'Customer - PEO') && 
			isThisSAASNewContract;
	}

	/**
	 * Creates all steps involved in the current wizard.
	 * Navigation is handled by the base class.
	 */
	public void setupSteps() {
		clearSteps();

		addStep(Page.EnterContract, 'Welcome', true, false, false);
		addStep(Page.EnterContractAccount, 'Account', false, false, false);
		addStep(Page.EnterContractLocation, 'Location', false, false, false);
		addStep(Page.EnterContractOpportunity, 'Opportunity', false, false, false);
		addStep(Page.EnterContractProducts, 'Products', false, false, false);
		addStep(Page.EnterContractFees, 'Fees', false, false, false);
		addStep(Page.EnterContractTerms, 'Terms', false, false, false);
		

		if (isOpportunityClosed) {
			addStep(Page.EnterContractAdministration,
				'Administration', false, isPresales, false);

			if (!isPresales) {
				addStep(Page.EnterContractDocument, 'Document', false, bReadOnly, false);

				if (!bReadOnly)
					addStep(Page.EnterContractSubmit, 'Submit', false, true, false);
			}
		} else
			addStep(Page.EnterContractAdministration,
				'Administration', false, true, false);
	}

	/**
	 * @return TRUE if the information in the accoutn section is correct
	 */
	private Boolean isAccountValid() {
		if (account.Escrow_Agent__c != null &&
				account.Escrow_Agreement_Date__c == null) {
			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR,
				'Escrow agreement date is required when an escrow agent is selected.'));
			return false;
		}

		return true;
	}

	private Boolean isSplitValid() {
		if (!bOpportunitySplit) 
			return true;

		resetNullsOnOpportunitySplits();
		if (opportunity.Do_Not_Deduct_From_SQC__c == false &&
				opportunity.Total_SQC__c - (opportunity.SQC_Amount__c + 
					opportunity.Split_Salesperson_1__c +
					opportunity.Split_Salespersons_2__c) != 0) {
			apexpages.addmessage(new ApexPages.Message(
				ApexPages.Severity.ERROR,
				'Total SQC amount was not distributed correctly.'));
			return false;
		}
		
		// split 1 if condition
		if(bOpportunitySplit &&
				opportunity.Split_Salesperson_1__c!=null &&
				opportunity.Split_Salesperson_1__c > 0 &&
				opportunity.split_salesperson__c == null){
			apexpages.addmessage(new ApexPages.Message(ApexPages.Severity.ERROR,
				'Split is set to Yes and split amount exists for salesperson1. ' +
				'Please select a valid salesperson1'));
			return false;
		}
		// split 2 if condition
		if (bOpportunitySplit &&
				opportunity.Split_Salespersons_2__c!=null &&
				opportunity.Split_Salespersons_2__c > 0 &&
				opportunity.Split_Salesperson_2__c == null){
			apexpages.addmessage(new ApexPages.Message(ApexPages.Severity.ERROR,
				'Split is set to Yes and split amount exists for salesperson2. ' +
				'Please select a valid salesperson2'));
			return false;
		}

		if (opportunity.Spilt__c>100) {
			apexpages.addmessage(new ApexPages.Message(ApexPages.Severity.ERROR,
				'Split Salesperson-1 % is greater than 100'));
			return false;
		}

		if (opportunity.Split_Salesperson_percent__c>100){
			apexpages.addmessage(new ApexPages.Message(ApexPages.Severity.ERROR,
				'Split Salesperson-2 % is greater than 100'));
			return false;
		}

		if (opportunity.OwnerId == opportunity.Split_Salesperson_2__c ||
				opportunity.ownerId == opportunity.split_salesperson__c) {
			apexpages.addmessage(new ApexPages.Message(ApexPages.Severity.ERROR,
				'Opportunity owner and Split Salesperson cannot be the same user.'));
			return false;
		}

		return true;
	}

	public Pagereference submit() {
		// to submit, the address must be validated
		if (!isAddressValidated()) {
			ApexPages.addmessage(new ApexPages.message(ApexPages.severity.ERROR,
				'Address needs to be validated. ' +
				'Go to Location tab and Edit Address to Validate.'));
			return null;
		}

		if (isFilesEmpty() && 
		 		contractAdmin.Document_Links__c == null && 
				 fileIds.size() == 0 ) {
			ApexPages.addmessage(new ApexPages.message(ApexPages.severity.ERROR,
				'Please upload a contract file to continue'));
			return null;
		}

		bSubmitAllChanges = true;
		return null;
	}

	private void validateSave() {
		bError = !isSplitValid() || !isAddressValidationReady();

		if (isOpportunityClosed &&
				!String.isBlank(account.Type) &&
				!account.Type.toLowerCase().contains('customer')) {
			bError = true;
			ApexPages.addMessage(
				new ApexPages.Message(ApexPages.Severity.ERROR,
					'Please select a valid customer type.'));
			bSubmitAllChanges = false;
		}
	}

	/**
	 * @param e
	 * @param operation
	 */
	private void addError(Exception e, String operation) {
		String errormessage = 
			'An error occurred while ' + operation + 
			'. All other changes will be saved but can NOT be' +
			' SUBMITTED until all errors are fixed.';

		ApexPages.addMessage(new ApexPages.Message(
			ApexPages.Severity.ERROR, errormessage));
		ApexPages.addMessage(new ApexPages.Message(
			ApexPages.Severity.ERROR, e.getMessage() + '\n' + e.getStackTraceString()));

		bSubmitAllChanges = false;
		account.RecordTypeId = prevAcctRT;
		opportunity.RecordTypeId = prevOppRT;
	}

	public Pagereference exitTool() {
		List<ContentDocument> cdoc;
		// if a file is uploaded and exiting the tool without saving delete the file.
		if (fileNotSaved && 
				ContentDocumentId != null &&
				!ContentDocumentId.isEmpty())
			delete [
				SELECT Id 
				FROM ContentDocument 
				WHERE Id IN :ContentDocumentId
			];

		return new PageReference('/' + opportunityId);
	}

	public PageReference saveAccount() {
		Account billingAddressAccount;
		RecordType customerRecordType;

		validateSave();
		if(!bError) {
			if (isThisSAASNewContract && !contractAdmin.Amended_And_Restated__c) {
				account.Customer_As_Of__c = contractadmin.Contract_Effective_Date__c;
			}

			if (bCopyTolegalName) 
				account.Legal_Name__c = account.Name;
			
			if (bCopyToShippingAddress) {
				billingAddressAccount = getBillingAddressAccount();
				account.ShippingCity = billingAddressAccount.BillingCity;
				account.ShippingCountry = billingAddressAccount.BillingCountry;
				account.ShippingPostalCode = billingAddressAccount.BillingPostalCode;
				account.ShippingState = billingAddressAccount.BillingState;
				account.ShippingStreet = billingAddressAccount.BillingStreet;
			}

			// if ready to finalize changesconvert to customer if not already so.

			if (isSubmitAndGood()) {
				customerRecordType = 
					USGRecordTypes.getRecordTypeByDeveloperName(
						'Account_CustomerRecordType');
				if (account.recordtypeid != customerRecordType.Id)
					account.recordtypeid = customerRecordType.Id;
			}

			if (isThisNonCoreContract)
				account.UltiPro_Processing_Type__c = 
					ContractWriteUpUtil.CONTRACT_TYPE_NONCORE;

			try {
				update account;
				loadAccount();

				// neelima 07/20/2015- moving document association to after 
				// account save to get the ar number for new accounts.

				if (fileIds != null && fileIds.size() > 0 && !bDocumentAssociated)
					AssociateDocumentWithAccount();
				else if (contractAdmin.Content_Distribution_Id__c != null &&
						(isThisNonCoreContract || isThisSAASNewContract))
					setDocumentTitle(
						contractAdmin.Content_Distribution_Id__c.split(','));
			} catch (exception e) {
				addError(e, 'saving Account');
			}
		}

		if (bError)
			bSubmitAllChanges = false;

		return null;
	}

	// create/update contract admin
	public void saveContractadmin(){
		contractadmin.Book_Month__c = opportunity.Book_Month__c;
		contractadmin.Book_year__c = opportunity.Book_year__c;
		contractadmin.Total_Contract_EEs__c =
			opportunity.Contracted_Number_of_Employees__c;
		contractadmin.Contract_Type__c = contractType;
		contractadmin.IsTestingProductsCheckbox__c = includeTestProducts ;

		// defaults
		if (isContractEELessThan300() && hasCoreProducts()) {
			if (contractAdmin.Launch_Period_Mo_s__c == null)
	contractAdmin.Launch_Period_Mo_s__c = C360_Default_Values_Setting.Launch_Period_Mo_s__c;
			
			if (String.isBlank(contractAdmin.Launch_Services_Expire_mo_s__c))
contractAdmin.Launch_Services_Expire_mo_s__c = C360_Default_Values_Setting.Launch_Services_Expire_mo_s__c;
		}

		if (contractadmin.Inital_Term__c && 
				contractadmin.Initial_Contract_Term__c != null)
			contractadmin.Subscription_Fee_Term_Prior_to_Incr__c =
				contractadmin.Initial_Contract_Term__c;
		
		try {
			upsert contractAdmin;
		} catch (Exception e) {
			addError(e,'Saving Contract Administration');
		}
	}

	/**
	 * Called when Split oppotunity sheckbox changes	
	 */
	public void changeSplitOpportunity() {
		// TODO: when needed, write code
		// that should be executed when the split opportunity
		// consideration changes.
	}

	/**
	 * @return PageReference
	 */
	public PageReference saveOpportunity() {
		Map<Id,Opportunity> mapOpportunitiesByIds =
			new Map<Id,Opportunity>();
		Map<id,Contract_Writeup__c> oppIdTocontractWriteUpMap =
			new Map<id,Contract_Writeup__c>();
		List<Contract_Writeup_Fees__c> feesToDelete;
		Set<Id> productIdsToDelete = new Set<Id>();
		String cwStatus;

		// if no error... we proceed
		if (!bError) {
			// no error at this point
			saveContractAdmin();
			ContractWriteUpUtil.ISOPPLINEITEMASSIGNED = true;

			// delete products from opportunity if needed.
			if (!productsToDelete.isEmpty()) {
				for (Id oliId : productsToDelete.keySet())
					productIdsToDelete.add(productsToDelete.get(oliId).Product2Id);

				if (contractWriteup.Id != null)
					feesToDelete = 
						ContractWriteUpUtil.getContractWriteUpFeesByProduct(
							contractWriteup.Id, productIdsToDelete);

				try {
					delete productsToDelete.values();
				} catch (exception e) {
					addError(e, 'deleting Products');
				}

				if (feesToDelete != null && !feesToDelete.isEmpty()) {
					try {
						delete feesToDelete;
					} catch (exception e) {
						addError(e, 'deleting Fees');
					}
				}
			}

			// save opportunity Products. If opportunity is set to 
			// closed assets will be created from these products.
			if (!opportunityproductsMap.isEmpty())
				try {
					for (OpportunityLineItem oli : opportunityproductsMap.values())
						oli.SQC_Contract_EE_s__c = oli.Active_Employees__c;
					
					upsert opportunityProductsMap.values();
				} catch (exception e) {
					addError(e, 'saving opportunity Products');
				}

			opportunity.Split__c = bOpportunitySplit ? 'Yes' : 'No';

			// if the opportunity split check box is off empty the split
			// fields in case there were previously populated
			if (!bOpportunitySplit) {
				opportunity.Split_salesperson__c = null;
				opportunity.Split_Salesperson_2__c = null;
				opportunity.Spilt__c = null;
				opportunity.Split_Salesperson_percent__c = null;
				opportunity.Split_Salesperson_1__c = null;
				opportunity.Split_Salespersons_2__c = null;
				opportunity.Split_Salesperson_1_Manager__c = null;
				opportunity.Spilt_Salesperson_Divison__c = null;
				opportunity.Split_Salesperson_1_Unit__c = null;
				opportunity.Spilt_Salesperson_2_Divison__c = null;
				opportunity.Split_Salesperson_2_Manager__c = null;
				opportunity.Split_Salesforce_2_Unit__c = null;
				opportunity.Do_Not_Deduct_From_SQC__c = false;
				opportunity.ERM_Account_Band_1__c = null;
				opportunity.ERM_Account_Band_2__c = null;
			}
			
			opportunity.Contract_Administration__c = contractAdmin.Id;
			// if submitting and no error, we move to draft
			cwStatus = isSubmitAndGood() ? 'Draft' : 'Pending Draft';
			try {
				// if the contract admin is new, 
				// or writeup has not been created, we create the writeup
				// we update the writeup record
				ContractWriteUpUtil.updateWriteUpRecord(
					contractWriteup, opportunity, contractAdmin, cwStatus);

				// we create all fees for contract write up
				ContractWriteUpUtil.createContractWriteUpFees(
					new Map<Id, Contract_Writeup__c> {
						opportunity.Id => contractWriteup
					});
			} catch (Exception e) {
				addError(e, 'saving Contract Writeup and Fees');
			}

			// if submitting...
			if (isSubmitAndGood()) {
				// all changes Convert to opportunity to closed won.
				if (opportunity.RecordTypeId != closedRecordType.Id)
					opportunity.RecordTypeId = closedRecordType.Id;

				// and we also nee to create an 
				// amendment for the contract writeup
				try {	
					AmendmentUtil.createAmendmentFromContractWriteup(
						new List<Contract_Writeup__c> { contractWriteup });
				} catch (Exception e) {
					addError(e, 'creating Amendment');
				}
			}

			opportunity.SCM_Contract_Administration_ID__c = contractWriteup.Id;
			// finally, we save the opportunity
			try {
				update opportunity;
			} catch (Exception e) {
				addError(e, 'saving Opportunity');
			}
		}

		if (bError) {
			bSubmitAllChanges = false;
			return null;
		} else
			return new PageReference('/' + opportunity.Id);
	}

	public void resetInitialContractTerms() {
		if (contractadmin.Milestone_Event__c == 'Coterminous with Agreement')
			contractAdmin.Initial_Contract_Term__c = null;
	}

	/**
	 * @return true if we are submitting and there are no errors
	 */
	private Boolean isSubmitAndGood() {
		return bSubmitAllChanges && !bError;
	}

	/**
	 * Uploads the current file
	 * @return  Pagereference
	 */
	public Pagereference uploadDocument() {
		ContentVersion insertedCv;

		// we attempt to insert the current file
		try {
			insert file;
		} catch (Exception ex) {
			ApexPages.addmessage(new ApexPages.message(
				ApexPages.severity.ERROR,
				'The file could not be uploaded. ' + ex.getMessage()));
			return null;
		}

		// we add to list of files
		fileIds.add(file.id);

		// we also nee the content document id
		insertedCv = [
			SELECT Id, 
				ContentDocumentId, 
				Title,
				PathOnClient
			FROM ContentVersion
			WHERE Id = :file.Id
		];

		ContentDocumentId.add(insertedCv.ContentDocumentId);
		insertedFiles.add(insertedCv);
		mpCDTitles.put(insertedCv.ContentDocumentId, insertedCv.Title);

		// we clar the file fo future entries
		file = new ContentVersion();
		return null;
	}

	/**
	 * Deletes the current file
	 * @return Pagereference
	 */
	public Pagereference deleteDocument() {
		ContentVersion cv = insertedFiles.get(selectedFileIndex);

		// first, we remove from db
		try {
			delete [
				SELECT Id 
				FROM ContentDocument
				WHERE Id = :cv.ContentDocumentId
			];
		} catch (Exception ex) {
			ApexPages.addmessage(new ApexPages.message(
				ApexPages.severity.ERROR,
				'The file could not be deleted. ' + ex.getMessage()));
			return null;
		}

		// then, we remove from each list
		insertedFiles.remove(selectedFileIndex);
		fileIds.remove(selectedFileIndex);
		ContentDocumentId.remove(selectedFileIndex);
		mpCDTitles.remove(cv.ContentDocumentId);

		return null; // selectedFileIndex
	}

	/**
	 * Create a sharing link from each document to the account.
	 */
	public void associateDocumentWithAccount() {
		String cvName, documentLinks,
			documentLinksTemplate = '<a href="' + 
				URL.getSalesforceBaseUrl().toExternalForm() + '/{0}">{1}</a><br/>';
		ContentDocumentLink cdl;
		List<ContentDocumentLink> listcdl;
		List<ContentDocument> lstCDtoUpdate;

		fileNotSaved = false;
		listcdl = new List<ContentDocumentLink>();

		// we fetch the exisintg documents
		lstCDtoUpdate = [
			SELECT Id, Title 
			FROM ContentDocument 
			WHERE Id =: ContentDocumentId
		];

		for (ContentDocument cd : lstCDtoUpdate) {
			cdl = new ContentDocumentLink();
			cdl.shareType = 'V';
			cdl.LinkedEntityId = account.Id;
			cdl.contentDocumentId = cd.Id;

			cvName = getDocumentTitle(account, mpCDTitles.get(cd.Id));
			documentLinks = String.format(documentLinksTemplate,
				new List<String> { cd.Id, cvName });
			
			// we update the title of the current document
			cd.Title = cvName;

			// we add to link to the contract admin
			if (String.isBlank(contractadmin.Document_Links__c))
				contractadmin.Document_Links__c = documentLinks;
			else if (!contractadmin.Document_Links__c.contains(documentLinks))
				contractadmin.Document_Links__c += documentLinks;

			listcdl.add(cdl);
		}

		// we add collaborators is ny is specified ini the setting
		GroupShareUtil.addCollaborators(ContentDocumentId);

		// we insert the sharing links and update the title of the documents
		insert listcdl;
		update lstCDtoUpdate;
		bDocumentAssociated = true;

		// we need to remove all pending documents
		// as they have all been properly shared at this point
		fileIds.clear();
		ContentDocumentId.clear();
		insertedFiles.clear();
		mpCDTitles.clear();
	}

	/**
	* neelimab 02/05/2016 biz-5240
	* adding logic to set the document title in case a previous doc
	* was uploaded with an incorrect format
	* might be process errored during submit or user uploaded doc and 
	* save and close for further updates (no ar on account at that time)
	* Fernando Gomez: Performance improvements applied.
	*/
	private void setDocumentTitle(List<Id> contentDistributionId) {
		String expectedTitle;
		List<String> links = new List<String>();

		for (ContentDistribution cd : [
					SELECT id,
						Name,
						ContentVersionId,
						ContentVersion.title,
						DistributionPublicUrl 
					FROM Contentdistribution 
					WHERE id in :ContentDistributionId
				]) {
			expectedTitle = getDocumentTitle(account,
				cd.ContentVersion.title);

			if (String.isNotBlank(expectedTitle) && 
					!cd.Name.equals(expectedTitle))
				cd.Name = expectedTitle;

			links.add('<a href="' + cd.DistributionPublicUrl + '">' + 
				EncodingUtil.urlEncode(cd.Name, 'UTF-8') + '</a>');
		}

		contractAdmin.Document_Links__c = String.join(links, '<br/>');
	}



private String getDocumentTitle(Account a,String t){
String strTitle;
String contractEffectiveDate;
// query for account ar#. this is needed as account might get ar number in the same save if it is a brand new customer
if(String.isNotBlank(a.AR__c)){
	if (isThisSAASNewContract) {
		if (contractAdmin.Contract_Effective_Date__c <> null) {
			contractEffectiveDate = contractAdmin.Contract_Effective_Date__c.format();


			strTitle = a.ar__c  + ' - ' + GeneralUtils.getStringAfterSpecialChar('~', t) + ' - ' + contractEffectiveDate;
		} else {
			strTitle = a.ar__c + ' - ' + GeneralUtils.getStringAfterSpecialChar('~', t);
		}

	   if(strTitle.length()>100){
		   strTitle=strTitle.subString(0, 100);
	   }
   }else if(isThisNonCoreContract){
	   strTitle=a.ar__c+ ' - '+GeneralUtils.getStringAfterSpecialChar('~',t);
	   if(strTitle.length()>100){
		   strTitle=strTitle.subString(0, 100);
	   }
   }else{
	   strTitle=t;
	   if(strTitle.length()>100){
		   strTitle=strTitle.subString(0, 100);
	   }
   }
}else{
   strTitle = t;
}

if(String.isNotBlank(strTitle)) strTitle= strTitle.left(255);
return strTitle;
}

	private void resetNullsOnOpportunitySplits() {
		opportunity.Total_SQC__c =
			(opportunity.Total_SQC__c == null ? 0 : opportunity.Total_SQC__c);
		opportunity.Split_Salesperson_1__c =
			(opportunity.Split_Salesperson_1__c == null) ? 0 :
				opportunity.Split_Salesperson_1__c;
		opportunity.Split_Salespersons_2__c =
			(opportunity.Split_Salespersons_2__c == null) ? 0 :
				opportunity.Split_Salespersons_2__c;
		opportunity.Spilt__c =
			(opportunity.Spilt__c == null) ? 0 : opportunity.Spilt__c;
		opportunity.Split_Salesperson_percent__c =
			(opportunity.Split_Salesperson_percent__c == null) ? 0 : 
				opportunity.Split_Salesperson_percent__c;
		opportunity.Do_Not_Deduct_From_SQC__c =
			(opportunity.Do_Not_Deduct_From_SQC__c == null) ? false :
				opportunity.Do_Not_Deduct_From_SQC__c;
		opportunity.SQC_Amount__c =
			(opportunity.SQC_Amount__c == null)? 0 : opportunity.SQC_Amount__c;
	}

	// split opportunity logic
	public void calculateSQC() {
		resetNullsOnOpportunitySplits();
		if (opportunity.Spilt__c != null && opportunity.Spilt__c > 0)
			opportunity.Split_Salesperson_1__c=
				(opportunity.Spilt__c / 100) * opportunity.Total_SQC__c;

		if (opportunity.Split_Salesperson_percent__c != null &&
				opportunity.Split_Salesperson_percent__c > 0)
			opportunity.Split_Salespersons_2__c =
				(opportunity.Split_Salesperson_percent__c / 100) *
					opportunity.Total_SQC__c;
		
		if(opportunity.Do_Not_Deduct_From_SQC__c)
			opportunity.SQC_Amount__c = opportunity.Total_SQC__c;
		else
			opportunity.SQC_Amount__c =
				opportunity.Total_SQC__c -
					(opportunity.Split_Salesperson_1__c +
					opportunity.Split_Salespersons_2__c);
	}

	public void calculateSQCByFlatAmt() {
		resetNullsOnOpportunitySplits();
		if(opportunity.Do_Not_Deduct_From_SQC__c)
			opportunity.SQC_Amount__c = opportunity.Total_SQC__c;
		else
			opportunity.SQC_Amount__c = opportunity.Total_SQC__c -
				(opportunity.Split_Salesperson_1__c +
				opportunity.Split_Salespersons_2__c);
	}

	public void calSplit1Amt() {
		calculateSQC();
	}

	public void calSplit1Pct(){
		// use try carch in case if invalid total sqc like negative,zero, null etc
		try {
			opportunity.Spilt__c =
				(opportunity.Split_Salesperson_1__c / 
					opportunity.Total_SQC__c) * 100;
		} catch (exception e) {
			opportunity.Spilt__c = 0;
		}

		calculateSQCByFlatAmt();
	}

	public void calSplit2Amt() {
		calculateSQC();
	}

	public void calSplit2Pct(){
		// use try carch in case if invalid total sqc like negative,zero, null etc
		try {
			opportunity.Split_Salesperson_percent__c =
				(opportunity.Split_Salespersons_2__c / 
					opportunity.Total_SQC__c) * 100;
		} catch (exception e) {
			opportunity.Split_Salesperson_percent__c = 0;
		}

		calculateSQCByFlatAmt();
	}

	public void calConcurrentUsers() {
		Decimal newValue, contractEmployees, userCalculationPer1000;

		contractEmployees = opportunity.Contracted_Number_of_Employees__c;
		userCalculationPer1000 = contractadmin.User_Calculation_per_1000__c;
		
		if (isEnterprise() && 
				contractEmployees != null && 
				userCalculationPer1000 != null) {
			contractEmployees = opportunity.Contracted_Number_of_Employees__c;
			userCalculationPer1000 = contractadmin.User_Calculation_per_1000__c;

			newValue = userCalculationPer1000 + 
				// this formula needs revision
				(contractEmployees <= 1000 ? 0 :
					Math.ceil((contractEmployees - 100) / 200));

			contractadmin.Concurrent_Users__c = newValue;
			contractadmin.Cog8_Author__c = newValue;
		}
	}

	/**
	 * Cacades the contract EE count into all products
	 */
	public void updateEECount() {
		if (opportunity.Contracted_Number_of_Employees__c != null)
			for (ProductSelectionWrapper psw : selectedProducts)
				if (!(psw.isCoreBundle || psw.isPrintBundle) && 
						!doNotCopyEEForProds.contains(
							psw.priceBookEntry.Product2.Name))
					psw.oppLineItem.Active_Employees__c = 
						opportunity.Contracted_Number_of_Employees__c;
	}

public void setUserInfoForOppOwner()
{
if(opportunity.ownerId==null) return;
User u= getUserInfo(opportunity.ownerId);
setUserInfoForOppOwner(u);
}

private void setUserInfoForOppOwner(user u){
if(u!=null){
   opportunity.Division_Region__c=u.division;
}
}

public void setUserInfoForSplit1()
{
if(opportunity.split_salesperson__c==null) return;
User u= getUserInfo(opportunity.split_salesperson__c);
setUserInfoForSplit1(u);
}

private void setUserInfoForSplit1(User u) {
if(u!=null){
   opportunity.Spilt_Salesperson_Divison__c=u.division;
   opportunity.Split_Salesperson_1_Manager__c=u.ManagerId;
}
}
public void setUserInfoForSplit2()
{
if(opportunity.Split_Salesperson_2__c==null) return;
User u= getUserInfo(opportunity.Split_Salesperson_2__c);
setUserInfoForSplit2(u);
}

private void setUserInfoForSplit2(user u){
if(u!=null){
   opportunity.Spilt_Salesperson_2_Divison__c=u.division;
   opportunity.Split_Salesperson_2_Manager__c=u.ManagerId;
}
}

private User getUserInfo(id userid)
{
User u= [select division, manager__c,ManagerId from User where id= :userId];
return u;
}

private Map<id,User> getUserInfo(set<id> userids)
{
return new Map<Id,user>([select division, manager__c,ManagerId from User where id in :userids]);
}

	public void setBookYear() {
		opportunity.Book_Year__c = String.valueof(
			contractadmin.Contract_Effective_Date__c.Year());
	}

	public void setOpportunityDefaults() {
		Boolean bDefaultPrimaryUnit = false;
		if (opportunity.Primary_Salesperson_Unit__c == null &&
				!contractadmin.Amended_And_Restated__c &&
				(isThisSAASNewContract  || isThisNonCoreContract)){
			bDefaultPrimaryUnit = true;
		}

		opportunity.Primary_Salesperson_Unit__c = bDefaultPrimaryUnit ? 1 :
			opportunity.Primary_Salesperson_Unit__c;

		defaultOpportunityName();
	}

private void resetSignatureNotRequired ()
{
if(!IsAdditionalBusiness) {
   contractAdmin.Signature_Not_Required__c=false;
}// end if(contractType!=....
}

private void setSubmitText(){
if(isThisSAASNewContract || isThisNonCoreContract){
   submitText='Click Submit to convert this prospect to a customer,generate the AR#, Create Purchase History records and automatically notify the distribution.';
}else if(IsAdditionalBusiness){
   submitText='Click Submit to create Purchase History records and automatically notify the distribution.';
}
}

	/**
	 * Moves to the specified page. Before moving, it performs the necessary
	 * setup and validation in the current page
	 * @return a reference to the destination page.
	 */
	public override PageReference jumpToPage() {
		NavigationPage currentNavPage, nextNavPage;
		String currentNavUrl;
		PageReference result;

		currentNavPage = steps.get(curStep);
		currentNavUrl = currentNavPage.thePage.getUrl();
		nextNavPage = steps.get(jumpToStep);

		if (jumpToStep == null || !steps.containsKey(jumpToStep)) {
			ApexPages.addmessage(new ApexPages.message(
					ApexPages.severity.ERROR, 'Destination page does not exists.'));
			return null;
		}

		// if we are in read-only mode, we don't need to do anything..
		// if not, we need some processing after each page
		if (!bReadOnly) {
			// actions to take when EnterContract is being edited
			if (currentNavUrl == Page.EnterContract.getUrl()) {
				// we set initial values contract type if null. 
				// if contract type has changed, we clear products 
				// (selcted & available) and reset the temp contarct type
				if (contractTypeTemp == null)
					contractTypeTemp = contractType;
				else if (contractTypeTemp != contractType) {
					selectedProducts = null;
					availableProducts = null;
					contractTypeTemp = contractType;
				}

				resetSignatureNotRequired();
				setSubmitText();
				
				// default for opportunintites
				setOpportunityDefaults();
			} 
			// actions to take when EnterContractAccount is being edited
			else if (currentNavUrl == Page.EnterContractAccount.getUrl()) {
				// we need to check info in the accoint information
				if (!isAccountValid())
					return null;
                else{
						if (isThisSAASNewContract){
							ContractAdministrationUtil.AssignDefaultValues(contractadmin, C360_Default_Values_Setting);
							ContractAdministrationUtil.AssignDefaultValues(contractWriteup, C360_Default_Values_Setting);
			} 
					}
			} 
			// actions to take when EnterContractLocation is being edited
			else if (currentNavUrl == Page.EnterContractLocation.getUrl()) {
				// to be able to move to the next page the user must not be
				// in the middle of editing or validating the address
				// we make sure the user if not in the middle of a validation
				if (!isAddressValidationReady())
					return null;
			}
			// actions to take when EnterContractOpportunity is being edited
			else if (currentNavUrl == Page.EnterContractOpportunity.getUrl()) {
				// we need to make sure split is valid
				// if split was specified
				if (!isSplitValid())
					return null;
			} 
			/*
			// actions to take when EnterContractProducts is being edited
			else if (currentNavUrl == Page.EnterContractProducts.getUrl()) {
				
			}
			*/
			// actions to take when EnterContractFees is being edited
			/*
			else if (currentNavUrl == Page.EnterContractFees.getUrl()) {
				// ...	
			}
			*/
			// actions to take when EnterContractUsers is being edited
			/*
			else if (currentNavUrl == Page.EnterContractUsers.getUrl()) {
				// ...	
			}
			*/
			/*
			// actions to take when EnterContractDocument is being edited
			else if (currentNavUrl == Page.EnterContractDocument.getUrl()) {
				// ...
			}
			*/
			// actions to take when EnterContractSubmit is being edited
			/*
			else if (currentNavUrl == Page.EnterContractSubmit.getUrl()) {
				// ...	
			}
			*/
		}

		result = steps.get(jumpToStep).thePage;
		result.setRedirect(false);

		curStep = jumpToStep;
		jumpToStep = null;
		return result;
	}

	/**
	 * Navigates to the next page in the navigation order.
	 * Implemented from abstract method in base class.
	 * @return a page reference to the next page.
	 */
	public override PageReference next() {
		jumpToStep = steps.get(curStep).next;
		return jumpToPage();
	}

	/**
	 * Navigates to the previos page in the navigation order.
	 * Implemented from abstract method in base class.
	 * @return a page reference to the next page.
	 */
	public override PageReference previous(){
		jumpToStep = steps.get(curStep).previous;
		return jumpToPage();
	}

	/**
	 * Called when Signature Requirement changes	
	 */
	public void changeSignatureRequired() {
		// TODO: when needed, write code
		// that should be executed when the signature
		// requirement changes
	}

	/**
	 * Adding logic for the text box testing products BIZ 3563
	 */
	public void addTestingProductsIfCheckBoxSelected() {
		Set<Id> pbeIds;
		List<Integer> indexes;
		Integer index;

		if (includeTestProducts) {
			index = 0;
			pbeIds = new Set<Id>();
			indexes = new List<Integer>();

			// first, we need to extract those products 
			// that have a text environment product specified
			// and that product has not already been adde...
			for (ProductSelectionWrapper sw : selectedProducts) 
				if (String.isNotBlank(sw.priceBookEntry.Product2.Test_Environment__c))
					pbeIds.add(sw.priceBookEntry.Product2.Test_Environment__c);
			
			// we proceed if we found test environments
			if (!pbeIds.isEmpty()) {
				// we look in the available products to find the indexes
				// of the products that are testing environments
				for (ProductSelectionWrapper aw : availableProducts) {
					// if we found a test nev product, we record the index
					if (pbeIds.contains(aw.priceBookEntry.Product2Id))
						indexes.add(index);
					// we increase the index to keep in sync with the products
					index++;
				}

				// if we found some indexes (meaning we have the tes env product)
				// we add them using the standard way
				if (!indexes.isEmpty()) {
					productIndexes = String.join(indexes, ',');
					addProducts();
				}
			}
		}
	}

	/**
	 * This method will be invoked when the use chooses to edit the address,
	 * No redirection is allowed here since the component is in-progress.
	 */
	public void handleOnEdit() {
		addressValidationStage = 1;
	}

	/**
	 * This method will be invoked the chooses to validate an address
	 * No redirection is allowed here since the component is in-progress.
	 */
	public void handleOnValidated() {
		addressValidationStage = 2;
	}

	/**
	 * This method will be invoked after the user selects to cancel the edition.
	 * No redirection is allowed here since the component is in-progress.
	 */
	public void handleOnCancel() {
		addressValidationStage = 0;
	}

	/**
	 * This method will be invoked after an address has been validated and saved.
	 * @return a page reference to allow redirection to another page since
	 * after save, the current interation has completed. Implementing
	 * methods should return null is the component is supposed to stay in the page.
	 */
	public PageReference handleOnSave() {
		addressValidationStage = 0;
		return null;
	}

	/**
	 * This method will be invoked when the validation fails, which could
	 * happen if the address is not found, or any other problem happens
	 * in the integration.
	 * @param message
	 */
	public void handleOnError(String message) {
		/*
		ApexPages.addMessage(new ApexPages.Message(
			ApexPages.Severity.ERROR,
			message == '' ?
				'Click Validate, Reset, or Cancel buttons to complete Edit Address'));
		*/
	}

	/**
	 * @return true if the user is in the middle of a validation attempt
	 */
	private Boolean isAddressValidationReady() {
		// if the status is 1 (editing) or 2 (validating)
		// it means the user has to either complete or cancel the validation
		if (addressValidationStage == 1 || addressValidationStage == 2) {
			ApexPages.addMessage(new ApexPages.Message(
				ApexPages.Severity.ERROR,
				'You must Validate, Save, Reset, or Cancel ' +
				'the Address Validation in order to move on to another step.'));
			return false;
		}

		return true;
	}

	/**
	 * @return true if the billing address has been validates
	 */
	private Boolean isAddressValidated() {
		return AddressValidatorCtrl.isAddressValidated(account.Id);
	}

	/**
	 * @return Existent Opportunity Products.
	 */
	private List<OpportunityLineItem> getExistentOpportunityProducts() {
		return [
			SELECT Id,
				Active_Employees__c, 
				Book_Year__c,
				Book_Month__c,
				OpportunityId, 
				PricebookEntryId,
				OT_Fee__c,
				Subscription_Fee__c,
				Product_Name__c,
				Product2Id,
				SQC_Contract_EE_s__c,
				Is_Core_Bundled__c,
				Is_Print_Bundled__c
			FROM OpportunityLineItem
			WHERE OpportunityId = :opportunityId
		];
	}

	/**
	 * @return true if the are no files
	 */
	public Boolean isFilesEmpty() {
		return ContentDocumentId.isEmpty();
	}

	/**
	 * @return true if the opportunity has core products
	 */
	private Boolean hasCoreProducts() {
		return [
			SELECT COUNT()
			FROM OpportunityLineItem 
			WHERE OpportunityId = :opportunity.Id
			AND Is_Core__c = TRUE
		] > 0;
	}

	/**
	 * @return true if contract EE is less or equal than 300 
	 */
	private Boolean isContractEELessThan300() {
		return opportunity.Contracted_Number_of_Employees__c <= 300;
	}

	/**
	 * @param productName
	 * @return 
	 */
	private Decimal getInitialActiveEmployees(String productName) {
		return productName == 'HR360' ? 2 : 0;
	}

	/**
	 * Just the billing address of the current account
	 */
	private Account getBillingAddressAccount() {
		return [
			SELECT BillingStreet,
				BillingCity,
				BillingState,
				BillingPostalCode,
				BillingCountry
			FROM Account
			WHERE Id = :account.Id
		];
	}

	/**
	 * Product Wrapper
	 */
	public class ProductSelectionWrapper implements Comparable {
		public PricebookEntry priceBookEntry { get; set; }
		public OpportunityLineItem oppLineItem { get; set; }

		public Boolean isCore { get; set; }
		public Boolean isPrint { get; set; }
		public Boolean isTest { get; set; }

		public Boolean isAvailableForCoreBundle { get; set; }
		public Boolean isAvailableForPrintBundle { get; set; }

		public Boolean isCoreBundle { get; set; }
		public Boolean isPrintBundle { get; set; }

		public Boolean isVisible { get; set; }

		/**
		 * @param priceBookEntry
		 * @param oppLineItem
		 * @param isCore
		 * @param isPrint
		 * @param isTest
		 * @param isAvailableForCoreBundle
		 * @param isAvailableForPrintBundle
		 * @param isCoreBundle
		 * @param isPrintBundle
		 */
		private ProductSelectionWrapper(
				PricebookEntry priceBookEntry, OpportunityLineItem oppLineItem, 
				Boolean isCore, Boolean isPrint, Boolean isTest, 
				Boolean isAvailableForCoreBundle, Boolean isAvailableForPrintBundle,
				Boolean isCoreBundle, Boolean isPrintBundle, Boolean isVisible) {
			this.priceBookEntry = priceBookEntry;
			this.oppLineItem = oppLineItem;

			this.isCore = isCore;
			this.isPrint = isPrint;
			this.isTest = isTest;

			this.isAvailableForCoreBundle = isAvailableForCoreBundle;
			this.isAvailableForPrintBundle = isAvailableForPrintBundle;

			this.isCoreBundle = isCoreBundle;
			this.isPrintBundle = isPrintBundle;

			this.isVisible = isVisible;
		}

		/**
		 * @param 
		 * @param 
		 */
		public Integer compareTo(Object obj) {
			ProductSelectionWrapper p1 = (ProductSelectionWrapper)obj;
			return priceBookEntry.Product2.Name.compareTo(
				p1.priceBookEntry.Product2.Name);
		}
	}

	/**
	 * Throwable exception
	 */
	public class NoAccessException extends Exception { }
}
