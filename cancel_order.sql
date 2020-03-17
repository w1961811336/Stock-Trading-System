if(object_id('cancel_id', 'P') is not null)
    drop procedure cancel_order
go
create procedure cencel_order
    @user_id bigint, @order_id bigint
as
begin
    set NOCOUNT ON;
    set XACT_ABORT ON;      --开启产生运行时错误，整个事务将终止并回滚
    
    declare @cancel_price int, @cancel_type int, 
            @cancel_undealed int, @cancel_stock_id int;
    
    --如果该用户id下不存在该订单，返回-1x--
    if not exists(select *
                 from orders
                 where order_id=@order_id and user_id=@user_id)
        return -1
    
    begin try
        --对可能出现异常的处理，或者判断
        --对临时表的操作也可以在这里进行，在上面或者这里定义都可以
        --添加事务保证下面的行级锁保持到事务的结束(ROWLOC、XLOCK必须放在事务中)
        
        begin transaction;
            --对数据库库的操作在事务中。
            --锁会在事务结束后释放。不管是回退还是提交。都会释放
            --变动前锁定指定数据
            select @cancel_type=type, @cancel_undealed=undealed,
                    @cancel_price=price, @cancel_stock_id=stock_id
            from orders
            --with(XLOCK, ROWLOCK, READPAST) ---排他锁,行级锁，指明数据库引擎返回结果时忽略加锁的行或数据页
            --readpast说明：不会返回锁定的记录，缺点是，其他操作不返回锁定的记录，只到事务释放才会释放锁
            with(XLOCK, ROWLOCK) 
            where order_id=@order_id and user_id=@user_id
            
            --锁定后变更该订单的数据
            update orders set canceled = dealed + undealed + canceled, undealed = 0
                where order_id=@order_id and user_id=@user_id
            
            if @cancel_type=0
            begin
                --取消的是买单, 需要解冻相关人民币
                --变动前锁定指定数据
                select *
                    from users
                    with(XLOCK, ROWLOCK) 
                    where user_id = @user_id
                
                --锁定后变更该用户的数据
                update users set cny_free = cny_free + @cancel_price * @cancel_undealed,
                        cny_freezed = cny_freezed - @cancel_price * @cancel_undealed
                        where user_id = @user_id
            end
            
            if @cancel_type=1
            begin
                --如果是卖单，需要解冻相关股票
                --变动前锁定指定数据
                select *
                    from user_position
                    with(XLOCK, ROWLOCK) 
                    where user_id = @user_id and stock_id = @cancel_stock_id
                
                --锁定后变更该用户持有股票的数据
                update user_position set num_free = num_free + @cancel_undealed,
                        num_freezed = num_freezed - @cancel_undealed
                        where user_id = @user_id and stock_id = @cancel_stock_id
            end
            SELECT 0 AS ErrorCode,'cancel succeed' AS ErrorMsg;
		    commit transaction
            return 0
	end try
    begin catch
		rollback transaction;
        --不知道如何使用
		select -2 as errorCode, 'cancel failure' as errorMsg;  
        --事务出现失败
        return -2
	end catch
end