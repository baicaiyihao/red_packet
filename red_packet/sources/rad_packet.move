module timetest::red_packet {
    use moveos_std::timestamp::{Self, Timestamp};
    use moveos_std::object::{Self, Object, ObjectID};
    use moveos_std::tx_context;
    use moveos_std::address;
    use moveos_std::signer;
    use moveos_std::bcs;
    use moveos_std::hash::sha3_256;
    use moveos_std::event;
    use std::vector;

    use rooch_framework::coin;
    use rooch_framework::coin_store::{Self, CoinStore};
    use rooch_framework::account_coin_store;

    const EAlreadyClaimed: u64 = 1;
    const ENotInSpecifiedRecipients: u64 = 2;

    struct RedPacket<phantom T> has key, store {
        id: ObjectID,
        sender: address,
        amount: u64,
        left_amount: u64,
        coin_type: String,
        coin_store: Object<CoinStore<FSC>>,
        original_amount: u64,
        claimer_addresses: vector<address>,
        specified_recipient: Option<vector<address>>
    }

    struct NewRedPacket<phantom T> has copy, drop {
        red_packet_id: ObjectID,
        sender: address,
        amount: u64,
        coin_type: String,
        coin_amount: u64,
    }

    struct ClaimRedPacket<phantom T> has copy, drop {
        claim_red_packet_id: ObjectID,
        claimer: address,
        claim_amount: u64,
        claim_coin_type: String,
    }

    struct RED_PACKET has drop {}

    fun init(otw: RED_PACKET, account: &signer) {
        let admin = signer::address_of(account);
        let publisher = object::create(otw, account);
        object::transfer(publisher, admin);
        let admin_cap = AdminCap { id: object::new(account) };
        object::transfer(admin_cap, admin);
    }

    public entry fun send_new_red_packet<T>(
        amount: u64,
        coin_amount: Coin<T>,
        specified_recipient: Option<vector<address>>,
        account: &signer
    ) {
        let sender = signer::address_of(account);
        let id = object::new(account);
        let red_packet_id = object::new(id);
        let coin_amount_num = coin::value(&coin_amount);

        let coin_amount = coin::into_balance(coin_amount);

        let coin_type = type_name::get<T>();
        let coin_type_string = *type_name::borrow_string(&coin_type);

        event::emit(NewRedPacket<T> {
        red_packet_id,
        sender,
        amount,
        coin_type: coin_type_string,
        coin_amount: coin_amount_num,
        });

        let red_packet = RedPacket<T> {
            id,
            sender,
            amount,
            left_amount:amount,
            coin_type: coin_type_string,
            coin_amount,
            original_amount: coin_amount_num,
            claimer_addresses: vector::empty<address>(),
            specified_recipient,
        };

        object::share(red_packet);
    }

    public entry fun claim_red_packet<T>(
        red_packet:&mut RedPacket<T>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        assert!(!vector::contains(&red_packet.claimer_addresses, &sender), EAlreadyClaimed);

        if(!option::is_none(&red_packet.specified_recipient)) {
            let specified = option::borrow(&red_packet.specified_recipient);
            assert!(vector::contains(specified, &sender), ENotInSpecifiedRecipients);
        };

        let left_value = balance::value(&red_packet.coin_amount);
        let coin_type = type_name::get<T>();
        let coin_type_string = *type_name::borrow_string(&coin_type);

        let _log_claim_amount: u64 = 0;

        if (red_packet.left_amount == 1) {
            red_packet.left_amount = red_packet.left_amount - 1;
            let coin = coin::take(&mut red_packet.coin_amount, left_value, ctx);
            object::transfer(coin, sender);
            _log_claim_amount = left_value;
        } else {
            let max = (left_value / red_packet.left_amount) * 2;
            let claim_amount = get_random(max, ctx);
            let claim_split = balance::split(&mut red_packet.coin_amount, claim_amount);
            let claim_value = coin::from_balance(claim_split, ctx);
            red_packet.left_amount = red_packet.left_amount - 1;
            object::transfer(claim_value, sender);
            _log_claim_amount = claim_amount;
        };

        vector::push_back(&mut red_packet.claimer_addresses,sender);

        event::emit(ClaimRedPacket<T> {
            claim_red_packet_id: object::uid_to_inner(&red_packet.id),
            claimer: sender,
            claim_amount: _log_claim_amount,
            claim_coin_type: coin_type_string,
        })
    }

    public fun get_tx_hash(): vector<u8> {
        let tx_hash = tx_context::tx_hash();
        tx_hash
    }

    public fun u64_to_bytes(num: u64): vector<u8> {
        if (num == 0) {
            return b"0"
        };
        let bytes = vector::empty<u8>();
        while (num > 0) {
            let remainder = num % 10;
            num = num / 10;
            vector::push_back(&mut bytes, (remainder as u8) + 48);
        };
        vector::reverse(&mut bytes);
        bytes
    }

    public fun random_to_u64(bytes: vector<u8>): vector<u8>  {
        let len = vector::length(&bytes);

        let start_index = (len - 8);
        let selected_bytes = vector::empty<u8>();

        let i = 0;
        while (i < 8) {
            let byte = vector::borrow(&bytes, start_index + i);
            vector::push_back(&mut selected_bytes, *byte);
            i = i + 1;
        };
        vector::reverse(&mut selected_bytes);
        selected_bytes
    }
    public entry fun get_random(account: &signer, timestamp_obj: &Object<Timestamp>, max: u64) {
        let account_addr = signer::address_of(account);
        let timestamp = object::borrow(timestamp_obj);
        let now_seconds = timestamp::seconds(timestamp);
        let tx_hash = get_tx_hash();

        let random_vector = vector::empty<u8>();
        vector::append(&mut random_vector, address::to_bytes(&account_addr));
        vector::append(&mut random_vector, u64_to_bytes(now_seconds));
        vector::append(&mut random_vector, tx_hash);

        let temp1 = sha3_256(tx_hash);
        let tempnum = random_to_u64(temp1);

        let random_num_ex = bcs::to_u64(tempnum);
        let random_value = (random_num_ex % max);
        random_value
    }
}
