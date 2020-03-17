set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go



ALTER trigger [make_transactions] on [dbo].[orders] for insert 
as
    --声明orders中列属性的变量--
    declare @order_id bigint, @user_id bigint, @stock_id int, 
        @type int, @price money, @undealed int, @dealed int, @canceled int
    --将新插入记录的属性值赋值给变量--
    select @order_id=order_id, @user_id=user_id, @stock_id=stock_id,
        @type=type, @price=price, @undealed=undealed, 
        @dealed=dealed, @canceled=canceled from inserted;
    --如果user_position中没有该用户持有某个股票的信息，则进行插入初始数据--
    if not exists(select *
                from user_position
                where user_id = @user_id and stock_id = @stock_id)
    begin
        insert into user_position
            values(@user_id, @stock_id, 0, 0, 0)
    end
    --如果新的order是买单，则进行买单的操作--
    if @type = 0
    begin
        declare @sell_order_id bigint, @sell_user_id bigint,
            @sell_price money, @sell_order_undealed int, @sell_order_dealed int
        --获取所有卖单的游标，按照价格从小到大升序，日期升序排序，进行操作--
        declare sell_orders cursor for
            select order_id, user_id, price, undealed, dealed from orders 
            where type=1 and stock_id=@stock_id and 
            price<=@price and undealed>0
            order by price,create_date
        open sell_orders
        --一直循环，直到新的order的undealed数量为0或者不存在符合条件的卖单--
        while @undealed > 0
        begin
            --取一条卖单数据--
			fetch next from sell_orders into 
                @sell_order_id, @sell_user_id, @sell_price, 
                @sell_order_undealed, @sell_order_dealed
            --数据已全部取完，退出循环--
            if @@fetch_status!= 0 break
            --如果当前卖单记录的未处理数量小于需要处理的数量--
            if (@sell_order_undealed < @undealed)
            begin
				set @undealed = @undealed - @sell_order_undealed;
				set @dealed = @dealed + @sell_order_undealed;
				set @sell_order_dealed 
                    = @sell_order_dealed + @sell_order_undealed;
                --更新卖家的可用钱的数量--
                update users set cny_free=cny_free + @sell_order_undealed * @sell_price
                    where user_id=@sell_user_id
                --更新买家的可用钱的数量和冻结钱的数量--
                update users set cny_free=cny_free + 
                        @sell_order_undealed * @price - @sell_order_undealed * @sell_price, 
                        cny_freezed=cny_freezed - @sell_order_undealed * @price
                    where user_id=@user_id 
                --更新卖家拥有股票信息，这里只修改冻结股票数量--
                update user_position set
                    num_freezed = num_freezed - @sell_order_undealed
                    where user_id=@sell_user_id and stock_id=@stock_id
                --更新买家拥有股票信息，这里只修改可卖股票数量--
                update user_position set
                    num_free = num_free + @sell_order_undealed
                    where user_id=@user_id and stock_id=@stock_id 
                --将卖家未处理订单置为0，用于之后的更新信息--
				set @sell_order_undealed = 0;
                --更新卖家订单的信息--
				update orders set dealed=@sell_order_dealed, 
                    undealed=@sell_order_undealed
                    where order_id=@sell_order_id
				declare @new_trans_id bigint
                --transactions表的id以50000001开始--
				select @new_trans_id=isnull(max(trans_id)+1, 50000001) 
                    from transactions 
                --插入成功交易的信息--
				insert into transactions 
                    values(@new_trans_id, getdate(), @stock_id, @order_id, @sell_order_id, 
                    @sell_order_undealed, @sell_price, 0)
			end
			else if (@sell_order_undealed >= @undealed)
			begin
                --如果当前卖单记录的未处理数量大于需要处理的数量--
				set @sell_order_undealed = @sell_order_undealed - @undealed
				set @sell_order_dealed = @sell_order_dealed + @undealed
                --更新卖家的可用钱的数量--
                update users set cny_free=cny_free + @undealed * @sell_price
                    where user_id=@sell_user_id
                --更新买家的可用钱的数量和冻结钱的数量，因为成交的价格可能不是自己出的价格，所以可能存在退钱--
                update users set cny_free=cny_free + 
                        @undealed * @price - @undealed * @sell_price, 
                        cny_freezed=cny_freezed - @undealed * @price
                    where user_id=@user_id 
                --更新卖家拥有股票信息，这里只修改冻结股票数量--
                update user_position set
                    num_freezed = num_freezed - @undealed
                    where user_id=@sell_user_id and stock_id=@stock_id
                --更新买家拥有股票信息，这里只修改可卖股票数量--
                update user_position set
                    num_free = num_free + @undealed
                    where user_id=@user_id and stock_id=@stock_id 
                --更新卖家订单的信息--
				update orders set 
                    dealed=@sell_order_dealed, undealed=@sell_order_undealed
					where order_id=@sell_order_id
				select @new_trans_id=isnull(max(trans_id)+1, 50000001) 
                    from transactions 
                --插入成功交易的信息--
				insert into transactions values(@new_trans_id, 
                    getdate(), @stock_id, @order_id, @sell_order_id, @undealed, @sell_price, 0)
				set @dealed = @dealed + @undealed;
				set @undealed=0;
				break
			end
		end
        --更新买家订单的信息--
		update orders set dealed=@dealed, undealed=@undealed
			where order_id=@order_id
		close sell_orders
		deallocate sell_orders
	end
	else if @type = 1
    --如果新的order是卖单，则进行卖单的操作--
    begin
        declare @buy_order_id bigint, @buy_user_id bigint, @buy_price money, 
            @buy_order_undealed int, @buy_order_dealed int
        --获取所有买单的游标，按照价格从大到小升序，日期升序排序，进行操作--
        declare buy_orders cursor for
            select order_id, user_id, price, undealed, dealed from orders
            where type = 0 and stock_id=@stock_id and price>=@price and undealed>0
            order by price DESC,create_date
        open buy_orders
        --一直循环，直到新的order的undealed数量为0或者不存在符合条件的卖单--            
        while @undealed > 0
        begin
            --取一条买单数据--
            fetch next from buy_orders into
                @buy_order_id, @buy_user_id, @buy_price, @buy_order_undealed, @buy_order_dealed
            --若全部取完，则退出循环--
            if @@fetch_status!=0 break
            --当前买单未处理数小于需要处理数--
            if(@buy_order_undealed < @undealed)
            begin
                set @undealed = @undealed - @buy_order_undealed;
                set @dealed = @dealed + @buy_order_undealed;
                set @buy_order_dealed = @buy_order_dealed + @buy_order_undealed;
                --更新买家的冻结钱的数量信息，因为成交价是自己出的价，所以不存在退钱，所以可用钱数量不变--
                update users set
                    cny_freezed=cny_freezed - @buy_order_undealed * @buy_price
                    where user_id=@buy_user_id
                --更新卖家的可用钱的数量信息--
                update users set cny_free=cny_free + @buy_order_undealed * @buy_price
                    where user_id=@user_id 
                --更新买家拥有股票信息，这里只修改可卖股票数量--
                update user_position set
                    num_free = num_free + @buy_order_undealed
                    where user_id=@buy_user_id and stock_id=@stock_id
                --更新卖家拥有股票信息，这里只修改冻结股票数量--
                update user_position set
                    num_freezed = num_freezed - @buy_order_undealed
                    where user_id=@user_id and stock_id=@stock_id 
                --将买家家未处理订单置为0，用于之后的更新信息--
                set @buy_order_undealed = 0
                --更新买家的order信息--
                update orders set dealed=@buy_order_dealed, 
                    undealed=@buy_order_undealed
                    where order_id=@buy_order_id
                --获取transactions的id+1--
				select @new_trans_id=isnull(max(trans_id)+1, 50000001) 
                    from transactions 
                --将成交成功的数据插入transactions表中--
				insert into transactions 
                    values(@new_trans_id, getdate(), @stock_id, @order_id, @buy_order_id, 
                    @buy_order_undealed, @buy_price, 0)
            end
            else if (@buy_order_undealed >= @undealed)
			begin
                --如果买单的未处理数量大于需要处理的数量--
				set @buy_order_undealed = @buy_order_undealed - @undealed;
				set @buy_order_dealed = @buy_order_dealed + @undealed;
                --更新买家的冻结钱的数量信息，因为成交价是自己出的价，所以不存在退钱，所以可用钱数量不变--
                update users set
                    cny_freezed=cny_freezed - @undealed * @buy_price
                    where user_id=@buy_user_id
                --更新卖家的可用钱的数量信息--
                update users set cny_free=cny_free + @undealed * @buy_price
                    where user_id=@user_id 
                --更新买家的order信息--
				update orders set 
                    dealed=@buy_order_dealed, undealed=@buy_order_undealed
					where order_id=@buy_order_id
                --更新买家拥有股票信息，这里只修改可卖股票数量--
                update user_position set
                    num_free = num_free + @undealed
                    where user_id=@buy_user_id and stock_id=@stock_id
                --更新卖家拥有股票信息，这里只修改冻结股票数量--
                update user_position set
                    num_freezed = num_freezed - @undealed
                    where user_id=@user_id and stock_id=@stock_id 
                --获取transactions的id+1--
				select @new_trans_id=isnull(max(trans_id)+1, 50000001) 
                    from transactions 
                --将成交成功的数据插入transactions表中--
				insert into transactions values(@new_trans_id, 
                    getdate(), @stock_id, @order_id, @buy_order_id, @undealed, @buy_price, 0)
				set @dealed = @dealed + @undealed;
				set @undealed=0;
				break
			end
        end
        update orders set dealed=@dealed, undealed=@undealed
			where order_id=@order_id
		close buy_orders
		deallocate buy_orders
	end

