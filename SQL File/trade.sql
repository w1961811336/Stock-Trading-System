if (object_id('trade', 'P') is not null)
    drop procedure trade
go
create procedure trade 
    @user_id bigint, @stock_id bigint, @type int,
	@price money, @ammount int
as
begin
    set NOCOUNT on;
    set XACT_ABORT ON;
    
    --如果是买单，判断可用人民币数量是否够用--
    declare @buy_cny_free int, @sell_num_free int
    if @type = 0
    begin
        select @buy_cny_free=cny_free from users where user_id=@user_id
        --若可用人民币数量不够，返回-1--
        if @buy_cny_free < @price * @ammount return -1
    end
    --如果是卖单，判断可卖股票数量是否够用--
    if @type = 1
    begin
        select @sell_num_free=num_free 
            from user_position 
            where user_id=@user_id and stock_id=@stock_id
        --若可售的股票数量不够，返回-2--
        if @sell_num_free < @ammount return -2
    end
    begin try
		declare @new_order_id bigint
        --设置插入订单的id
        select @new_order_id=isnull(max(order_id)+1, 40000001) 
        from orders
        if @type = 0
        begin
            --买单操作，冻结相应的钱
            select *
            from users
            with(XLOCK, ROWLOCK)
            where user_id = @user_id
            
            --锁定后更新用户人民币信息
            update users set cny_free = cny_free - @price * @ammount,
            cny_freezed = cny_freezed + @price * @ammount
            where user_id = @user_id
        end
        if @type = 1
        begin
            --卖单操作，冻结相应的股票数量
            select *
            from user_position
            with(XLOCK, ROWLOCK)
            where user_id = @user_id and stock_id = @stock_id
            
            --锁定后更新用户股票信息
            update user_position set num_free = num_free - @ammount,
            num_freezed = num_freezed + @ammount
            where user_id = @user_id and stock_id = @stock_id
        end
        --以上操作结束后，执行插入操作
        insert into orders 
                    values(@new_order_id, getdate(),@user_id, @stock_id,
                           @type, @price, @ammount, 0, 0, 0)
        select 0 as ErrorCode, 'commit trade succeed' as ErrorMsg;
        commit transaction;
        return 0;
    end try
    begin catch
        rollback transaction;
        select -3 as ErrorCode, 'commit trade failure'
        return -3
    end catch
    
end