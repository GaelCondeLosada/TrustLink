module trusted_contract::trusted_contract {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::math;
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::option::{Self, Option};
    use sui::dynamic_field as dfield;
    use sui::dynamic_object_field as ofield;
    use sui::address;
    use 0x2::kiosk;
    use sui::bag::Bag;
    use std::string;
    use sui::clock::{Self, Clock};
    use std::vector;
    use sui::table::{Self, Table};
    use sui::bag::Self;

    //--- CONSTANTS -----------------------------------------------------------------------------

    // ----- different types of requirements (some can be added here) -----
    const ITEM_REQUIREMENT_FROM :             u64 = 0;
    const LOCKED_ITEM_REQUIREMENT :           u64 = 1;
    const CONFIRMATION_REQUIREMENT_FROM :     u64 = 2;
    const CONFIRMATION_REQUIREMENT_KEY_FROM : u64 = 3;

    // ----- different types of actions (some can be added here) -----
    const GIVE_ITEM :          u64 = 100;
    const UNLOCK_ITEM_ACTION : u64 = 101;

    // ----- types of errors -----
    const INTERNAL_ERROR :                         u64 = 200;
    const TEST_ERROR :                             u64 = 201;
    const NOT_AUTHORIZED_ERROR :                   u64 = 202;
    const ACTING_ON_A_FINISHED_CONTRACT_ERROR :    u64 = 203;
    const ITEM_NOT_PRESENT_ERROR :                 u64 = 204;
    const WRONG_KEY_ERROR :                        u64 = 205;
    const CONTRACT_HANDLES_DOESNT_MATCH_CONTRACT : u64 = 206;

    //--- STRUCTURES ----------------------------------------------------------------------------

    // main structure, contract that manages a trusted exchange
    struct TrustedContract has key {
        id : UID,
        creation_time : u64,                                // the time at which the contract was created (things can expire after a certain time in a contract)
        expiration_time : u64,                              // the time at which the contract will expire (if it is not finished before)
        steps : vector<ContractStep>,                       // despcription of the contract in form of steps (requirements and then actions)
        expiration_actions : vector<Action>,                // actions that will be executed when the contract expires
        has_lock_requirements : bool,                       // utility boolean to know if we have lock requirements in the contract
    }
    
    struct TrustedContractHandler has key {
        id : UID,
        contract_id : ID,
        state : ContractState,                              // The current state in the sequence of contract steps
        items_table : table::Table<ID, ItemContainer>,      // Bag that contains items for the contract 
        confirmations_table : table::Table<address, u64>,   // table that contains info on who has performed confirmations at which step of the contract
        confirmations_table_key : table::Table<ID, address>,// table that contains the keys for confirmations with key that were performed (map the key id to the address of the confirmator)
        utilityOption : option::Option<ItemContainer>       // utility option for methods... (see put_items)
    }

    // wrapper for the index that represent the contract state
    struct ContractState has store{
        step_index : u64,                 // index at which we are in the contract steps
        is_contract_finished : bool,      // if the contract is finished or not
        expired : bool                    // if the contract is expired or not 
    }

    // describe each step of a contract, is mutable and become immutable when used to create a contract
    struct ContractDescriptor has key, store {
        id : UID,
        steps : vector<ContractStep>,
        expiration_actions : vector<Action>, // actions that will be executed when the contract expires
        expiration_time : u64               // the time at which the contract will expire (if it is not finished before)
    }

    // a contract is composed of a sequence of contract steps that each has some requirement and then some actions (there can zero requirement or zero actions)
    struct ContractStep has store, copy, drop {
        requirements : vector<Requirement>, // requirements for this contract step to be valid
        actions :      vector<Action>       // when all requirements are fulfilled, the action will be executed
    }

    // Requirement to be fulfilled by the contract participants
    struct Requirement has store, copy, drop {
        type : u64,                 // type of requirement -> see constants at top
        item_id : ID,               // id of the item we want or we want locked or id of the key we want for a confirmation with key  
        wallet_address_1 : address, // address of the person who has to complete the requirement 
        wallet_address_2 : address  // address of the person who will be given the key in case of CONFIRMATION_REQUIREMENT_KEY_FROM
    }

    // Action that will be executed by the contract on certains conditions
    struct Action has store, copy, drop {
        type : u64,               // type of action -> see constats at top
        wallet_address : address, // address of the person the action will be executed for
        item_id_1 : ID,           // id of the first item we will act on
    }

    // wrapper around a contained item (that will be added dynamically) that knows the owner and the current lock state for the contract to know
    struct ItemContainer has key, store {
        id : UID,
        owner_address : address, // address of the person (wallet) that can retrieve the item if the container is not locked
        locked : bool,           // if the item is locked inside and cannot be retrieved
    }

    // key that allows a contract user to effectuate the action confirmate with key
    struct ConfirmationKey has key, store {
        id : UID
    }

    //--- INTERFACE -----------------------------------------------------------------------------

    // ----- for the contract descriptor ----- :

    /*
    * Create a contract descriptor for which we can change requirements and action and give it to the caller.
    * The descriptor can then be used to create a contract that can no longer change its requirements and actions.
    */
    public entry fun new_contract_descriptor(ctx: &mut TxContext){
        let firstStep = ContractStep{
            requirements : vector<Requirement>[], 
            actions : vector<Action>[],
            };
        let descriptor = ContractDescriptor{
            id : object::new(ctx), 
            steps : vector<ContractStep>[firstStep],
            expiration_actions : vector<Action>[],
            expiration_time : 0 // Expiration time is set to 0 by default, if it is not changed the contract will never expire
            };
        transfer::transfer(descriptor, tx_context::sender(ctx));
    }

    /*
    * Validates the current last contract step (pair of requirements and actions) of the contract descriptor and create a new one
    * To make the wanted contract descriptor the pattern is the following
    * - add requirements and actions to last step with the two following functions
    * - validate the step that contains all actions and requirements and will no longer be changeable and create a new step to add the next requirements and actions
    * - repeat...
    */
    public entry fun validate_step(contractDescriptor: &mut ContractDescriptor){
        let newStep = ContractStep{
            requirements : vector<Requirement>[], 
            actions : vector<Action>[],
            };
        vector::push_back<ContractStep>(&mut contractDescriptor.steps, newStep);
    }

    /*
    * Add a new requirement to the contract descriptor given in parameter, inside the last contract step it has.
    * @type : the type of requirement -> see constants on top
    * @item_id : the id of the item we, for example, require (in case of ITEM_REQUIREMENT_FROM) or we want locked (in case of LOCKED_ITEM_REQUIREMENT)
    * @wallet_address_1 : the address of the person (wallet) who has to fulfill the requirement, for example confirm a step (in case of CONFIRMATION_REQUIREMENT_FROM)
    * @wallet_address_2 : the address of the second person implicated in the requirement, that will be given the confirmation key (in case of CONFIRMATION_REQUIREMENT_KEY_FROM)
    */
    public entry fun add_requirement_to_description_step(contractDescriptor: &mut ContractDescriptor, type : u64, item_id : ID, wallet_address_1 : address, wallet_address_2 : address){
        let newRequirement = Requirement{type, item_id, wallet_address_1, wallet_address_2};
        let lastIndex = vector::length(&contractDescriptor.steps) - 1;
        let lastStep = vector::borrow_mut<ContractStep>(&mut contractDescriptor.steps, lastIndex);
        vector::push_back<Requirement>(&mut lastStep.requirements, newRequirement); 
    }

    /*
    * Add a new action to the contract descriptor given in parameter, inside the last contract step it has.
    * @type : the type of action -> see constants on top
    * @wallet_address : the person (wallet) the action will be done for, for example to which we will give authorization for an item (in case of GIVE_ITEM)
    * @item_id_1 : the id of the first item implicated in the action, for example the item to give to someone (in case of GIVE_ITEM)
    */
    public entry fun add_action_to_description_step(contractDescriptor: &mut ContractDescriptor, type : u64, wallet_address : address, item_id_1 : ID, _ : ID){ // we let the last id to not break the interface
        let newAction = Action{type, wallet_address, item_id_1};
        let lastIndex = vector::length(&contractDescriptor.steps) - 1;
        let lastStep = vector::borrow_mut<ContractStep>(&mut contractDescriptor.steps, lastIndex);
        vector::push_back<Action>(&mut lastStep.actions, newAction);
    }

    /*
    * Add expiration actions for if the contract expire (exeed his expiration time) -> it will execute the expiration actions
    */
    public entry fun add_expiration_action_to_description(contractDescriptor: &mut ContractDescriptor, type : u64, wallet_address : address, item_id_1 : ID, _ : ID){ // we let the last id to not break the interface
        let newAction = Action{type, wallet_address, item_id_1};
        vector::push_back<Action>(&mut contractDescriptor.expiration_actions, newAction);
    }
    
    /*
    * Set the life span of a contract in milliseconds, after the given time, the contract will expire, it will execute its expiration actions and be finished.
    * If not set, the contract will live until completed
    */
    public entry fun add_expiration_time_to_description(contractDescriptor: &mut ContractDescriptor, expiration_time : u64, clockAddress : &Clock){
        contractDescriptor.expiration_time = expiration_time + clock::timestamp_ms(clockAddress);
    }

    // ----- for the contract ----- :

    /*
    * Create a new contract (shared) from the given contract descriptor.
    * The contract description (steps) cannot be modified but users can iteract with it through the interface
    */
    public entry fun new_contract(contractDescriptor: &mut ContractDescriptor, clockAddress : &Clock, ctx: &mut TxContext){
        // we create the new state and contract
        let contractState = ContractState{step_index : 0, is_contract_finished : false, expired : false};
        let hasLockRequirements = internal_has_lock_requirement(&contractDescriptor.steps);
        let contract = TrustedContract{
            id : object::new(ctx), 
            creation_time : clock::timestamp_ms(clockAddress),
            expiration_time : 0, 
            steps : contractDescriptor.steps,
            expiration_actions : contractDescriptor.expiration_actions,
            has_lock_requirements : hasLockRequirements,
        };

        let contractHandler = TrustedContractHandler{
            id : object::new(ctx), 
            contract_id : object::id(&contract),
            state : contractState,
            items_table : table::new<ID, ItemContainer>(ctx),
            confirmations_table : table::new<address, u64>(ctx),
            confirmations_table_key : table::new<ID, address>(ctx),
            utilityOption : option::none()
        };

        internal_generate_keys_for_and_set_requirements(&mut contract.steps, ctx);
        transfer::share_object(contractHandler);
        transfer::freeze_object(contract);
    } 

    /*
    * Try to add an item in the contract. If the contract is already finished, will throw an ACTION_ON_A_FINISHED_CONTRACT_ERROR and transfer back the item to the caller
    * if the item is not required or the caller doesn't have the right, will throw a NOT_AUTHORIZED_ERROR
    */
    public entry fun put_item<T : key + store>(contract : &TrustedContract, contractHandler : &mut TrustedContractHandler, item : T, clockAddress : &Clock, ctx: &mut TxContext) { // put an item into a contract, will work only if there is a requirement for this item and the person calling the function
        assert!(contractHandler.contract_id == object::id(contract), CONTRACT_HANDLES_DOESNT_MATCH_CONTRACT);
        assert!(!internal_is_contract_finished(contractHandler), ACTING_ON_A_FINISHED_CONTRACT_ERROR); // is the contract already finished ?        
        let currentStep = vector::borrow<ContractStep>(&contract.steps, contractHandler.state.step_index); // the current contract step
        let done = false;
        let requirementIndex = 0;
        let nbRequirements = vector::length(&currentStep.requirements);
        while(!done && requirementIndex < nbRequirements){
            let requirement = vector::borrow(&currentStep.requirements, requirementIndex);
            if(requirement.type == ITEM_REQUIREMENT_FROM && requirement.wallet_address_1 == tx_context::sender(ctx)){ // is the requirement for this person to give an item ?
                if(requirement.item_id == object::id(&item)){ // is the requirement for this item ?
                    let itemContainer = ItemContainer{
                        id : object::new(ctx),
                        owner_address : tx_context::sender(ctx),
                        locked : false,
                    };
                    option::fill(&mut contractHandler.utilityOption, itemContainer);
                    done = true; // terminate the loop and exit without error
                }
            };
            requirementIndex = requirementIndex + 1;
        };

        if(option::is_some(&contractHandler.utilityOption)){
            let itemContainer = option::extract(&mut contractHandler.utilityOption);
            let itemId = object::id(&item);
            ofield::add(&mut itemContainer.id, object::id(&item), item);
            table::add<ID, ItemContainer>(&mut contractHandler.items_table, itemId, itemContainer);
            internal_update_contract(contract, contractHandler, clockAddress);
        } else {
            transfer::public_transfer(item, tx_context::sender(ctx)); // if we couldn't put it, give back the item
            assert!(done, NOT_AUTHORIZED_ERROR);
        };
    }

    /*
    * If a person has an item that the contract own, they can retrieve it they have owner rights on the item and if it is not lock or if the contract is finished
    * Otherwise will throw a NOT_AUTHORIZED_ERROR
    */
    public entry fun take_item<T : key + store>(contractHandler : &mut TrustedContractHandler, item_id : ID, ctx: &mut TxContext){ // Methode assez degeulasse a voir si on peut faire mieux
        assert!(table::contains<ID, ItemContainer>(&contractHandler.items_table, item_id), ITEM_NOT_PRESENT_ERROR); // do we have the item ?
        let contractFinished = internal_is_contract_finished(contractHandler);
        let itemContainer = table::borrow_mut<ID, ItemContainer>(&mut contractHandler.items_table, item_id);
        assert!(itemContainer.owner_address == tx_context::sender(ctx) && (!itemContainer.locked || contractFinished), NOT_AUTHORIZED_ERROR); // is the item owned by the caller ? can he take it ?
        // we can give him the item :
        let itemContainer = table::borrow_mut<ID, ItemContainer>(&mut contractHandler.items_table, item_id);
        let itemVal = ofield::remove<ID, T>(&mut itemContainer.id, item_id);
        transfer::public_transfer(itemVal, tx_context::sender(ctx)); // Transfering the Item back to the sender
    }

    /*
    * Borrow a mutable reference to an item inside the contract if they have owner rights on the item and if it is not lock, otherwise will throw a NOT_AUTHORIZED_ERROR
    * If the contract contains some LOCK_ITEM_REQUIREMENT will also throw a NOT_AUTHORIZED_ERROR
    */
    public fun borrow_item_mut<T : key + store>(contract : & TrustedContract, contractHandler : &mut TrustedContractHandler, item_id : ID, ctx: &mut TxContext) : &mut T{
        assert!(contractHandler.contract_id == object::id(contract), CONTRACT_HANDLES_DOESNT_MATCH_CONTRACT);
        assert!(!internal_is_contract_finished(contractHandler), ACTING_ON_A_FINISHED_CONTRACT_ERROR); // is the contract already finished ?   
        assert!(table::contains<ID, ItemContainer>(&contractHandler.items_table, item_id), ITEM_NOT_PRESENT_ERROR); // do we have the item ?
        let itemContainer = table::borrow_mut<ID, ItemContainer>(&mut contractHandler.items_table, item_id);
        assert!(itemContainer.owner_address == tx_context::sender(ctx), NOT_AUTHORIZED_ERROR); // is the item owned by the caller ? can he take it ?
        assert!(!itemContainer.locked || contract.has_lock_requirements, NOT_AUTHORIZED_ERROR); // if the item is locked or we have lock requirements we cannot give the mutable reference
        let itemContainer = table::borrow_mut<ID, ItemContainer>(&mut contractHandler.items_table, item_id);
        ofield::borrow_mut<ID, T>(&mut itemContainer.id, item_id)
    }

    /*
    * If a person has an item held in a contract to its name (is the owner) and the current contract step has a requirement to lock this item,
    * the person can lock the item by calling this function (will no longer be able to retrieve it until some action unlocks it).
    * Otherwise will throw a NOT_AUTHORIZED_ERROR
    */
    public entry fun lock_item<T : key + store>(contract : &TrustedContract, contractHandler : &mut TrustedContractHandler, item_id : ID, clockAddress : &Clock, ctx: &mut TxContext){ // lock an item already present in the contract, works only if the caller has authorization
        assert!(contractHandler.contract_id == object::id(contract), CONTRACT_HANDLES_DOESNT_MATCH_CONTRACT);
        assert!(!internal_is_contract_finished(contractHandler), ACTING_ON_A_FINISHED_CONTRACT_ERROR); // is the contract already finished ?
        assert!(table::contains<ID, ItemContainer>(&contractHandler.items_table, item_id), ITEM_NOT_PRESENT_ERROR); // so we have the item ?
        let currentStep = vector::borrow<ContractStep>(&contract.steps, contractHandler.state.step_index); // the current contract step
        let done = false;
        let requirementIndex = 0;
        let nbRequirements = vector::length(&currentStep.requirements);
        while(!done && requirementIndex < nbRequirements){
            let requirement = vector::borrow(&currentStep.requirements, requirementIndex);
            if(requirement.type == LOCKED_ITEM_REQUIREMENT && requirement.wallet_address_1 == tx_context::sender(ctx)){
                let itemContainer = table::borrow_mut<ID, ItemContainer>(&mut contractHandler.items_table, item_id); // we already know we have the item from previous assert
                assert!(itemContainer.owner_address == tx_context::sender(ctx), NOT_AUTHORIZED_ERROR); // does the caller have owner rights on the item ?
                itemContainer.locked = true;
                done = true; // exit loop and exit without error
            };
            requirementIndex = requirementIndex + 1;
        };
        if(done) internal_update_contract(contract, contractHandler, clockAddress);
        assert!(done, NOT_AUTHORIZED_ERROR);
    }

    /*
    * Return true if the item with the given address is in the given contract and is locked (if the contract is finished the items are all unlocked by default)
    */
    public fun is_item_locked<T : key + store>(contractHandler : &mut TrustedContractHandler, item_id : ID) : bool { 
        assert!(table::contains<ID, ItemContainer>(&contractHandler.items_table, item_id), ITEM_NOT_PRESENT_ERROR); // do we have the item ?
        if(internal_is_contract_finished(contractHandler)){
            false
        } else {
            let itemContainer = table::borrow<ID, ItemContainer>(&contractHandler.items_table, item_id);
            itemContainer.locked
        }
    }

    /*
    * Tells if the given contract contains the item with the given id
    */
    public fun contains_item(contractHandler : &TrustedContractHandler, item_id : ID) : bool {
        table::contains<ID, ItemContainer>(&contractHandler.items_table, item_id)
    }

    /*
    * If the give contract has a CONFIRMATION_REQUIREMENT_FROM at its current step, one can call this function to confirmate that they want to confirmate the step.
    * If there is no requirement needing a confirmation, will throw a NOT_AUTHORIZED_ERROR
    */
    public entry fun confirm_step(contract : &TrustedContract, contractHandler : &mut TrustedContractHandler, clockAddress : &Clock, ctx: &mut TxContext){
        assert!(contractHandler.contract_id == object::id(contract), CONTRACT_HANDLES_DOESNT_MATCH_CONTRACT);
        assert!(!internal_is_contract_finished(contractHandler), ACTING_ON_A_FINISHED_CONTRACT_ERROR); // is the contract already finished
        let currentStep = vector::borrow<ContractStep>(&contract.steps, contractHandler.state.step_index); // the current contract step
        let done = false;
        let requirementIndex = 0;
        let nbRequirements = vector::length(&currentStep.requirements);
        while(!done && requirementIndex < nbRequirements){
            let requirement = vector::borrow(&currentStep.requirements, requirementIndex);
            if(requirement.type == CONFIRMATION_REQUIREMENT_FROM && requirement.wallet_address_1 == tx_context::sender(ctx)){ // is it a valid request ?
                if(table::contains<address, u64>(&contractHandler.confirmations_table, tx_context::sender(ctx))){ // if we already have a confirmation we need to remove it and add an updated confirmation
                    table::remove<address, u64>(&mut contractHandler.confirmations_table, tx_context::sender(ctx));
                };
                table::add<address, u64>(&mut contractHandler.confirmations_table, tx_context::sender(ctx), contractHandler.state.step_index); // add the cofirmation to the table
                done = true; // stop loop and exit without error
            };
            requirementIndex = requirementIndex + 1;
        };
        if(done) internal_update_contract(contract, contractHandler, clockAddress);
        assert!(done, NOT_AUTHORIZED_ERROR);
    }

    /*
    * If the give contract has a CONFIRMATION_REQUIREMENT_KEY_FROM at its current step, one can call this function with the right key (given to someone when the step started) to confirmate 
    * that they want to confirmate the step.
    * If there is no requirement needing a confirmation, will throw a NOT_AUTHORIZED_ERROR, if the key is wrong will throw a WRONG_KEY_ERROR
    */
    public entry fun confirmate_step_with_key(contract : &TrustedContract, contractHandler : &mut TrustedContractHandler, key : &ConfirmationKey, clockAddress : &Clock, ctx : &mut TxContext){
        assert!(contractHandler.contract_id == object::id(contract), CONTRACT_HANDLES_DOESNT_MATCH_CONTRACT);
        assert!(!internal_is_contract_finished(contractHandler), ACTING_ON_A_FINISHED_CONTRACT_ERROR); // is the contract already finished
        let currentStep = vector::borrow<ContractStep>(&contract.steps, contractHandler.state.step_index); // the current contract step
        let done = false;
        let requirementIndex = 0;
        let nbRequirements = vector::length(&currentStep.requirements);
        while(!done && requirementIndex < nbRequirements){
            let requirement = vector::borrow(&currentStep.requirements, requirementIndex);
            if(requirement.type == CONFIRMATION_REQUIREMENT_KEY_FROM && requirement.wallet_address_1 == tx_context::sender(ctx)){ // is it a valid request ?
                assert!(requirement.item_id == object::id(key), WRONG_KEY_ERROR); // did the caller put the right key
                table::add<ID, address>(&mut contractHandler.confirmations_table_key, object::id(key), tx_context::sender(ctx)); // add the cofirmation to the table with the key id as key
                done = true; // stop loop and exit without error
            };
            requirementIndex = requirementIndex + 1;
        };
        if(done) internal_update_contract(contract, contractHandler, clockAddress);
        assert!(done, NOT_AUTHORIZED_ERROR);
    }

    /* 
    * Cancelling the contract allows each sender to take back his items.
    * The sender could then freely can take_item on the items he gave or he was given.
    */
    public entry fun cancel_contract(contractHandler : &mut TrustedContractHandler){ 
        assert!(!internal_is_contract_finished(contractHandler), ACTING_ON_A_FINISHED_CONTRACT_ERROR); // is the contract already finished
        internal_finish_contract(contractHandler); // will restore the items to their owners
    }


    //--- INTERNAL ------------------------------------------------------------------------------

    // If requirement of the given contract (at its current state) are fulfilled, update the state and execute necessary actions
    fun internal_update_contract(contract : &TrustedContract, contractHandler : &mut TrustedContractHandler, clockAddress : &Clock){
        if(contract.expiration_time != 0 && clock::timestamp_ms(clockAddress) > contract.expiration_time){ // If contract is expired we execute the expiration actions
            internal_execute_actions(contractHandler, &contract.expiration_actions); // execute the expiration actions
            contractHandler.state.expired = true; // we mark the contract as expired
            internal_finish_contract(contractHandler); // we finish the contract
        }
        else {
            let currentStep = *vector::borrow<ContractStep>(&contract.steps, contractHandler.state.step_index); // copy the current step
            if(internal_are_requirements_met(contractHandler, &currentStep.requirements)){ // are requirements met ?
                internal_execute_actions(contractHandler, &currentStep.actions);
                contractHandler.state.step_index = contractHandler.state.step_index + 1; // we increment the state => go to the next step
                if(contractHandler.state.step_index >= vector::length(&contract.steps)) internal_finish_contract(contractHandler); // if we have no steps left, we finish the contract
            };
        }
    }

    // Check if the given contract fulfills all the given requirements
    fun internal_are_requirements_met(contractHandler : &TrustedContractHandler, requirements : &vector<Requirement>) : bool { // verify that all requirements of a ContractStep are met
        let allRequirementsMet = true;
        let requirementIndex = 0;
        let nbRequirements = vector::length(requirements);
        while(allRequirementsMet && requirementIndex < nbRequirements){
            let requirement = vector::borrow<Requirement>(requirements, requirementIndex);
            if(requirement.type == ITEM_REQUIREMENT_FROM){ // test if the item requirement is fulfilled
                if(table::contains<ID, ItemContainer>(&contractHandler.items_table, requirement.item_id)) { // do we have the item ?
                    let itemContainer = table::borrow<ID, ItemContainer>(&contractHandler.items_table, requirement.item_id);
                    if(itemContainer.owner_address != requirement.wallet_address_1) allRequirementsMet = false; // was the item put by the right person
                } else {
                    allRequirementsMet = false; // if we didn't have the item
                }
            } else if (requirement.type == LOCKED_ITEM_REQUIREMENT) { // test if the locked item requirement is fulfilled
                if(table::contains<ID, ItemContainer>(&contractHandler.items_table, requirement.item_id)){ // do we have the item ?
                    let itemContainer = table::borrow<ID, ItemContainer>(&contractHandler.items_table, requirement.item_id);
                    if(!itemContainer.locked) allRequirementsMet = false; // is the item really locked
                } else {
                    allRequirementsMet = false; // if we didn't have the item
                }
            } else if (requirement.type == CONFIRMATION_REQUIREMENT_FROM){ // test if the confirmation requirement is fulfilled
                if(table::contains<address, u64>(&contractHandler.confirmations_table, requirement.wallet_address_1)){ // do we have a confirmation from the good person ?
                    if(!(*table::borrow<address, u64>(&contractHandler.confirmations_table, requirement.wallet_address_1) == contractHandler.state.step_index)) allRequirementsMet = false; // is the confirmation for the current step ?
                } else {
                    allRequirementsMet = false; // if we didn't have the item
                }
            } else if(requirement.type == CONFIRMATION_REQUIREMENT_KEY_FROM){ // test if the confirmation requirement with key is fulfilled
                if(!table::contains<ID, address>(&contractHandler.confirmations_table_key, requirement.item_id)) allRequirementsMet = false; // no need to check the address (condition in the confirmation function)
            };
            requirementIndex = requirementIndex + 1;
        };
        allRequirementsMet
    }

    // Execute all the given actions on the given contract
    fun internal_execute_actions(contractHandler : &mut TrustedContractHandler, actions : &vector<Action>){ // execute all actions of a ContractStep (don't execute actions that can't be done -> for exapmle giving an item that the contract does not have)
        let actionIndex = 0;
        let nbActions = vector::length(actions);
        while(actionIndex < nbActions){
            let action = vector::borrow<Action>(actions, actionIndex);
            if(table::contains<ID, ItemContainer>(&contractHandler.items_table, action.item_id_1)){ // check that we really the item required to execute the action
                let itemContainer = table::borrow_mut<ID, ItemContainer>(&mut contractHandler.items_table, action.item_id_1);
                if(action.type == GIVE_ITEM) itemContainer.owner_address = action.wallet_address // switch the owner of the item if it is the action  
                else if (action.type == UNLOCK_ITEM_ACTION) itemContainer.locked = false; // unlock the item if it is the action
            };
            actionIndex = actionIndex + 1;
        }
    }

    // generate and transfer the key necessary for the confirmation requirement int the fiven steps with key and make the requirement match the key
    fun internal_generate_keys_for_and_set_requirements(steps : &mut vector<ContractStep>, ctx: &mut TxContext){
        let stepIndex = 0;
        let nbSteps = vector::length(steps);
        while(stepIndex < nbSteps){
            let requirementsVec = vector::borrow_mut(steps, stepIndex);
            let requirementIndex = 0;
            let nbRequirements = vector::length(&requirementsVec.requirements);
            while(requirementIndex < nbRequirements){
                let requirement = vector::borrow_mut(&mut requirementsVec.requirements, requirementIndex);
                if(requirement.type == CONFIRMATION_REQUIREMENT_KEY_FROM){
                    let newKey = ConfirmationKey{id : object::new(ctx)}; // create the key
                    requirement.item_id = object::id(&newKey); // set the requirement to match the key
                    transfer::transfer(newKey, requirement.wallet_address_2); // send the key to the person the requirement wants to
                };
                requirementIndex = requirementIndex + 1;
            };
            stepIndex = stepIndex + 1;
        }
    }

    // returns true if there are any LOCKED_ITEM_REQUIREMENTS in the given requirements
    fun internal_has_lock_requirement(steps : &vector<ContractStep>) : bool {
        let hasLockRequirement = false;
        let stepIndex = 0;
        let nbSteps = vector::length(steps);
        while(!hasLockRequirement && stepIndex < nbSteps){
            let requirementsVec = vector::borrow(steps, stepIndex);
            let requirementIndex = 0;
            let nbRequirements = vector::length(&requirementsVec.requirements);
            while(!hasLockRequirement && requirementIndex < nbRequirements){
                let requirement = vector::borrow(&requirementsVec.requirements, requirementIndex);
                if(requirement.type == ITEM_REQUIREMENT_FROM) hasLockRequirement = true;
                requirementIndex = requirementIndex + 1;
            };
            stepIndex = stepIndex + 1;
        };
        hasLockRequirement
    }

    // mark the given contract as finished -> the only think people will be able to do is take back items they own in the contract
    fun internal_finish_contract(contractHandler : &mut TrustedContractHandler){
        contractHandler.state.is_contract_finished = true;
    }

    // tell if the contract is finished
    fun internal_is_contract_finished(contractHandler : &TrustedContractHandler) : bool { // explicit
        contractHandler.state.is_contract_finished
    }

// ----- TESTS -----------------------------------------------------------------------------------------------------

    #[test]
    fun test_contract_descriptor() {
        use sui::test_scenario as ts;

        // init
        let userA = @0xA;
        let scenario = ts::begin(@0x0);
        
        // create dummy item
        let dummyItem = ConfirmationKey{id : ts::new_object(&mut scenario)};
        ts::next_tx(&mut scenario, userA);

        // execute transactions 
        ts::next_tx(&mut scenario, userA);
        new_contract_descriptor(ts::ctx(&mut scenario));
        
        ts::next_tx(&mut scenario, userA);
        let contractDescriptor = ts::take_from_sender<ContractDescriptor>(&mut scenario);
        add_action_to_description_step(&mut contractDescriptor, GIVE_ITEM, userA, object::id(&dummyItem), object::id(&dummyItem));
        ts::next_tx(&mut scenario, userA);
        add_requirement_to_description_step(&mut contractDescriptor, CONFIRMATION_REQUIREMENT_KEY_FROM, object::id(&dummyItem), userA, userA);
        ts::next_tx(&mut scenario, userA);
        validate_step(&mut contractDescriptor);

        // test assertions
        ts::next_tx(&mut scenario, userA);
        let firstStep = vector::borrow<ContractStep>(&contractDescriptor.steps, 0);
        let firstAction = vector::borrow<Action>(&firstStep.actions, 0);
        assert!(vector::length(&contractDescriptor.steps) == 2, TEST_ERROR);
        assert!(vector::length(&firstStep.requirements) == 1, TEST_ERROR);
        assert!(vector::length(&firstStep.actions) == 1, TEST_ERROR);
        assert!(firstAction.type == GIVE_ITEM, TEST_ERROR);
        assert!(firstAction.wallet_address == userA, TEST_ERROR);
        
        // clean
        ts::return_to_sender(&scenario, contractDescriptor);
        transfer::transfer(dummyItem, userA); // transfer so we can exit
        ts::end(scenario);
    }

    #[test]
    fun test_scenario_1() {
        use sui::test_scenario as ts;

        // init
        let userA = @0xA;
        let userB = @0xB;
        let scenario = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // create dummy item
        let dummyItem = ConfirmationKey{id : ts::new_object(&mut scenario)};
        ts::next_tx(&mut scenario, userA);
        transfer::transfer(dummyItem, userA); // give the item to A
        ts::next_tx(&mut scenario, userA);
        let dummyItem = ts::take_from_sender<ConfirmationKey>(&scenario);
        let dummyItemId = object::id(&dummyItem);

        // create the contract
        ts::next_tx(&mut scenario, userA);
        new_contract_descriptor(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        let contractDescriptor = ts::take_from_sender<ContractDescriptor>(&mut scenario);
        add_requirement_to_description_step(&mut contractDescriptor, ITEM_REQUIREMENT_FROM, object::id(&dummyItem), userA, userA);   // request item
        ts::next_tx(&mut scenario, userA);
        add_action_to_description_step(&mut contractDescriptor, GIVE_ITEM, userB, object::id(&dummyItem), object::id(&dummyItem)); // give item to use B
        ts::next_tx(&mut scenario, userA);
        new_contract(&mut contractDescriptor, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        ts::return_to_sender(&scenario, contractDescriptor);
        let contract = ts::take_immutable<TrustedContract>(&scenario);
        let contractHandler = ts::take_shared<TrustedContractHandler>(&scenario);

        // execute contract
        ts::next_tx(&mut scenario, userA);
        put_item(&contract, &mut contractHandler, dummyItem, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userB);
        take_item<ConfirmationKey>(&mut contractHandler, dummyItemId, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        
        // tests if B has the item
        ts::next_tx(&mut scenario, userB);
        let dummy = ts::take_from_sender<ConfirmationKey>(&scenario); // test if B has the item
        ts::return_to_sender(&scenario, dummy); // give it back so we can exit
        
        // clean
        clock::destroy_for_testing(clock);
        ts::return_shared<TrustedContractHandler>(contractHandler);
        ts::return_immutable<TrustedContract>(contract);
        ts::end(scenario);
    }

    #[test]
    fun test_scenario_2() {
        use sui::test_scenario as ts;

        // init
        let userA = @0xA;
        let userB = @0xB;
        let scenario = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // create dummy item
        let dummyItem = ConfirmationKey{id : ts::new_object(&mut scenario)};
        ts::next_tx(&mut scenario, userA);
        transfer::transfer(dummyItem, userA); // give the item to A
        ts::next_tx(&mut scenario, userA);
        let dummyItem = ts::take_from_sender<ConfirmationKey>(&scenario);
        let dummyItemId = object::id(&dummyItem);

        // create the contract
        ts::next_tx(&mut scenario, userA);
        new_contract_descriptor(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        let contractDescriptor = ts::take_from_sender<ContractDescriptor>(&mut scenario);
        add_requirement_to_description_step(&mut contractDescriptor, ITEM_REQUIREMENT_FROM, object::id(&dummyItem), userA, userA);   // request item
        ts::next_tx(&mut scenario, userA);
        add_requirement_to_description_step(&mut contractDescriptor, LOCKED_ITEM_REQUIREMENT, object::id(&dummyItem), userA, userA); // request item to be locked
        ts::next_tx(&mut scenario, userA);
        validate_step(&mut contractDescriptor);
        ts::next_tx(&mut scenario, userA);
        add_requirement_to_description_step(&mut contractDescriptor, CONFIRMATION_REQUIREMENT_KEY_FROM, object::id(&dummyItem), userA, userB); // request a confirmation from A but B has key
        ts::next_tx(&mut scenario, userA);
        add_action_to_description_step(&mut contractDescriptor, GIVE_ITEM, userB, object::id(&dummyItem), object::id(&dummyItem)); // give item to use B
        ts::next_tx(&mut scenario, userA);
        add_action_to_description_step(&mut contractDescriptor, UNLOCK_ITEM_ACTION, userB, object::id(&dummyItem), object::id(&dummyItem)); // unlock the item
        ts::next_tx(&mut scenario, userA);
        new_contract(&mut contractDescriptor, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        ts::return_to_sender(&scenario, contractDescriptor);
        let contractHandler = ts::take_shared<TrustedContractHandler>(&scenario);
        let contract = ts::take_immutable<TrustedContract>(&scenario);

        // execute contract
        ts::next_tx(&mut scenario, userA);
        put_item(&contract, &mut contractHandler, dummyItem, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        lock_item<ConfirmationKey>(&contract, &mut contractHandler, dummyItemId, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userB);
        let keyCap = ts::take_from_sender<ConfirmationKey>(&scenario);
        ts::next_tx(&mut scenario, userA);
        assert!(contractHandler.state.step_index == 1, TEST_ERROR);
        confirmate_step_with_key(&contract, &mut contractHandler, &keyCap, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userB);
        take_item<ConfirmationKey>(&mut contractHandler, dummyItemId, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        
        // tests if B has the item
        ts::next_tx(&mut scenario, userB);
        let dummy = ts::take_from_sender<ConfirmationKey>(&scenario); // test if B has the item
        ts::return_to_sender(&scenario, dummy); // give it back so we can exit
        
        // clean
        clock::destroy_for_testing(clock);
        ts::return_shared<TrustedContractHandler>(contractHandler);
        ts::return_immutable<TrustedContract>(contract);
        ts::return_to_sender(&scenario, keyCap);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = NOT_AUTHORIZED_ERROR)]
    fun test_scenario_fail_1() {
        use sui::test_scenario as ts;

        // init
        let userA = @0xA;
        let userB = @0xB;
        let scenario = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // create dummy item
        let dummyItem = ConfirmationKey{id : ts::new_object(&mut scenario)};
        ts::next_tx(&mut scenario, userA);
        transfer::transfer(dummyItem, userA); // give the item to A
        ts::next_tx(&mut scenario, userA);
        let dummyItem = ts::take_from_sender<ConfirmationKey>(&scenario);
        let dummyItemId = object::id(&dummyItem);

        // create the contract
        ts::next_tx(&mut scenario, userA);
        new_contract_descriptor(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        let contractDescriptor = ts::take_from_sender<ContractDescriptor>(&mut scenario);
        add_requirement_to_description_step(&mut contractDescriptor, ITEM_REQUIREMENT_FROM, object::id(&dummyItem), userA, userA);   // request item
        ts::next_tx(&mut scenario, userA);
        add_requirement_to_description_step(&mut contractDescriptor, LOCKED_ITEM_REQUIREMENT, object::id(&dummyItem), userA, userA); // request item to be locked
        ts::next_tx(&mut scenario, userA);
        validate_step(&mut contractDescriptor);
        ts::next_tx(&mut scenario, userA);
        add_requirement_to_description_step(&mut contractDescriptor, CONFIRMATION_REQUIREMENT_KEY_FROM, object::id(&dummyItem), userA, userB); // request a confirmation from A but B has key
        ts::next_tx(&mut scenario, userA);
        add_action_to_description_step(&mut contractDescriptor, GIVE_ITEM, userB, object::id(&dummyItem), object::id(&dummyItem)); // give item to use B
        ts::next_tx(&mut scenario, userA);
        add_action_to_description_step(&mut contractDescriptor, UNLOCK_ITEM_ACTION, userB, object::id(&dummyItem), object::id(&dummyItem)); // unlock the item
        ts::next_tx(&mut scenario, userA);
        new_contract(&mut contractDescriptor, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        ts::return_to_sender(&scenario, contractDescriptor);
        let contract = ts::take_immutable<TrustedContract>(&scenario);
        let contractHandler = ts::take_shared<TrustedContractHandler>(&scenario);

        // execute contract
        ts::next_tx(&mut scenario, userA);
        put_item(&contract, &mut contractHandler, dummyItem, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        lock_item<ConfirmationKey>(&contract, &mut contractHandler, dummyItemId, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        take_item<ConfirmationKey>(&mut contractHandler, dummyItemId, ts::ctx(&mut scenario)); // should not have authorization

        // clean
        clock::destroy_for_testing(clock);
        ts::return_shared<TrustedContractHandler>(contractHandler);
        ts::return_immutable<TrustedContract>(contract);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = WRONG_KEY_ERROR)]
    fun test_scenario_fail_2() {
        use sui::test_scenario as ts;

        // init
        let userA = @0xA;
        let userB = @0xB;
        let scenario = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // create dummy item
        let dummyItem = ConfirmationKey{id : ts::new_object(&mut scenario)};
        ts::next_tx(&mut scenario, userA);
        transfer::transfer(dummyItem, userA); // give the item to A
        ts::next_tx(&mut scenario, userA);
        let dummyItem = ts::take_from_sender<ConfirmationKey>(&scenario);
        let dummyItemId = object::id(&dummyItem);

        // create the contract
        ts::next_tx(&mut scenario, userA);
        new_contract_descriptor(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        let contractDescriptor = ts::take_from_sender<ContractDescriptor>(&mut scenario);
        add_requirement_to_description_step(&mut contractDescriptor, ITEM_REQUIREMENT_FROM, object::id(&dummyItem), userA, userA);   // request item
        ts::next_tx(&mut scenario, userA);
        add_requirement_to_description_step(&mut contractDescriptor, LOCKED_ITEM_REQUIREMENT, object::id(&dummyItem), userA, userA); // request item to be locked
        ts::next_tx(&mut scenario, userA);
        validate_step(&mut contractDescriptor);
        ts::next_tx(&mut scenario, userA);
        add_requirement_to_description_step(&mut contractDescriptor, CONFIRMATION_REQUIREMENT_KEY_FROM, object::id(&dummyItem), userA, userB); // request a confirmation from A but B has key
        ts::next_tx(&mut scenario, userA);
        validate_step(&mut contractDescriptor);
        ts::next_tx(&mut scenario, userA);
        add_action_to_description_step(&mut contractDescriptor, GIVE_ITEM, userB, object::id(&dummyItem), object::id(&dummyItem)); // give item to use B
        ts::next_tx(&mut scenario, userA);
        add_action_to_description_step(&mut contractDescriptor, UNLOCK_ITEM_ACTION, userB, object::id(&dummyItem), object::id(&dummyItem)); // unlock the item
        ts::next_tx(&mut scenario, userA);
        new_contract(&mut contractDescriptor, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        ts::return_to_sender(&scenario, contractDescriptor);
        let contract = ts::take_immutable<TrustedContract>(&scenario);
        let contractHandler = ts::take_shared<TrustedContractHandler>(&scenario);

        // create fake key
        let fakeKey = ConfirmationKey{id : ts::new_object(&mut scenario)};
        ts::next_tx(&mut scenario, userA);
        transfer::transfer(fakeKey, userA); // give the item to A
        ts::next_tx(&mut scenario, userA);
        let fakeKey = ts::take_from_sender<ConfirmationKey>(&scenario);

        // execute contract
        ts::next_tx(&mut scenario, userA);
        put_item(&contract, &mut contractHandler, dummyItem, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        lock_item<ConfirmationKey>(&contract, &mut contractHandler, dummyItemId, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        confirmate_step_with_key(&contract, &mut contractHandler, &fakeKey, &clock, ts::ctx(&mut scenario)); // A tries to confirmate with the wrong key
        
        // clean
        clock::destroy_for_testing(clock);
        ts::return_shared<TrustedContractHandler>(contractHandler);
        ts::return_immutable<TrustedContract>(contract);
        ts::return_to_sender(&scenario, fakeKey);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = NOT_AUTHORIZED_ERROR)]
    fun test_scenario_fail_3() {
        use sui::test_scenario as ts;

        // init
        let userA = @0xA;
        let userB = @0xB;
        let scenario = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // create dummy item
        let dummyItem = ConfirmationKey{id : ts::new_object(&mut scenario)};
        ts::next_tx(&mut scenario, userA);
        transfer::transfer(dummyItem, userA); // give the item to A
        ts::next_tx(&mut scenario, userA);
        let dummyItem = ts::take_from_sender<ConfirmationKey>(&scenario);
        let dummyItemId = object::id(&dummyItem);

        // create the contract
        ts::next_tx(&mut scenario, userA);
        new_contract_descriptor(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        let contractDescriptor = ts::take_from_sender<ContractDescriptor>(&mut scenario);
        add_requirement_to_description_step(&mut contractDescriptor, ITEM_REQUIREMENT_FROM, object::id(&dummyItem), userA, userA);   // request item
        ts::next_tx(&mut scenario, userA);
        add_requirement_to_description_step(&mut contractDescriptor, LOCKED_ITEM_REQUIREMENT, object::id(&dummyItem), userA, userA); // request item to be locked
        ts::next_tx(&mut scenario, userA);
        validate_step(&mut contractDescriptor);
        ts::next_tx(&mut scenario, userA);
        add_requirement_to_description_step(&mut contractDescriptor, CONFIRMATION_REQUIREMENT_KEY_FROM, object::id(&dummyItem), userA, userB); // request a confirmation from A but B has key
        ts::next_tx(&mut scenario, userA);
        validate_step(&mut contractDescriptor);
        ts::next_tx(&mut scenario, userA);
        add_action_to_description_step(&mut contractDescriptor, GIVE_ITEM, userB, object::id(&dummyItem), object::id(&dummyItem)); // give item to use B
        ts::next_tx(&mut scenario, userA);
        add_action_to_description_step(&mut contractDescriptor, UNLOCK_ITEM_ACTION, userB, object::id(&dummyItem), object::id(&dummyItem)); // unlock the item
        ts::next_tx(&mut scenario, userA);
        new_contract(&mut contractDescriptor, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        ts::return_to_sender(&scenario, contractDescriptor);
        let contract = ts::take_immutable<TrustedContract>(&scenario);
        let contractHandler = ts::take_shared<TrustedContractHandler>(&scenario);

        // execute contract
        ts::next_tx(&mut scenario, userA);
        put_item(&contract, &mut contractHandler, dummyItem, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        lock_item<ConfirmationKey>(&contract, &mut contractHandler, dummyItemId, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userB);
        let keyCap = ts::take_from_sender<ConfirmationKey>(&scenario);
        ts::next_tx(&mut scenario, userA);
        confirmate_step_with_key(&contract, &mut contractHandler, &keyCap, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        take_item<ConfirmationKey>(&mut contractHandler, dummyItemId, ts::ctx(&mut scenario)); // A tries to take an item that was given to B
        ts::next_tx(&mut scenario, userA);
        
        // clean
        clock::destroy_for_testing(clock);
        ts::return_shared<TrustedContractHandler>(contractHandler);
        ts::return_immutable<TrustedContract>(contract);
        ts::return_to_sender(&scenario, keyCap);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = NOT_AUTHORIZED_ERROR)]
    fun test_scenario_fail_4() {
        use sui::test_scenario as ts;

        // init
        let userA = @0xA;
        let userB = @0xB;
        let scenario = ts::begin(@0x0);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // create dummy item
        let dummyItem = ConfirmationKey{id : ts::new_object(&mut scenario)};
        ts::next_tx(&mut scenario, userA);
        transfer::transfer(dummyItem, userA); // give the item to A
        ts::next_tx(&mut scenario, userA);
        let dummyItem = ts::take_from_sender<ConfirmationKey>(&scenario);
        let dummyItemId = object::id(&dummyItem);

        // create the contract
        ts::next_tx(&mut scenario, userA);
        new_contract_descriptor(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        let contractDescriptor = ts::take_from_sender<ContractDescriptor>(&mut scenario);
        add_requirement_to_description_step(&mut contractDescriptor, ITEM_REQUIREMENT_FROM, object::id(&dummyItem), userA, userA);   // request item
        ts::next_tx(&mut scenario, userA);
        add_requirement_to_description_step(&mut contractDescriptor, LOCKED_ITEM_REQUIREMENT, object::id(&dummyItem), userA, userA); // request item to be locked
        ts::next_tx(&mut scenario, userA);
        validate_step(&mut contractDescriptor);
        ts::next_tx(&mut scenario, userA);
        add_requirement_to_description_step(&mut contractDescriptor, CONFIRMATION_REQUIREMENT_KEY_FROM, object::id(&dummyItem), userA, userB); // request a confirmation from A but B has key
        ts::next_tx(&mut scenario, userA);
        validate_step(&mut contractDescriptor);
        ts::next_tx(&mut scenario, userA);
        add_action_to_description_step(&mut contractDescriptor, GIVE_ITEM, userB, object::id(&dummyItem), object::id(&dummyItem)); // give item to use B
        ts::next_tx(&mut scenario, userA);
        add_action_to_description_step(&mut contractDescriptor, UNLOCK_ITEM_ACTION, userB, object::id(&dummyItem), object::id(&dummyItem)); // unlock the item
        ts::next_tx(&mut scenario, userA);
        new_contract(&mut contractDescriptor, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        ts::return_to_sender(&scenario, contractDescriptor);
        let contract = ts::take_immutable<TrustedContract>(&scenario);
        let contractHandler = ts::take_shared<TrustedContractHandler>(&scenario);

        // execute contract
        ts::next_tx(&mut scenario, userA);
        put_item(&contract, &mut contractHandler, dummyItem, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userA);
        lock_item<ConfirmationKey>(&contract, &mut contractHandler, dummyItemId, &clock, ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, userB);
        take_item<ConfirmationKey>(&mut contractHandler, dummyItemId, ts::ctx(&mut scenario)); // B tries to take the item before confirmation

        // clean
        clock::destroy_for_testing(clock);
        ts::return_shared<TrustedContractHandler>(contractHandler);
        ts::return_immutable<TrustedContract>(contract);
        ts::end(scenario);
    }

}