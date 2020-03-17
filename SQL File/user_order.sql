if (object_id('user_order', 'P') is not null)
    drop procedure user_order
go
create procedure user_order 
    @user_id bigint, @order_id bigint, @begin_date datetime, @end_date datetime,
	@stock_id int, @type int
as
begin
    --未对user_id是否为空进行判断
    if @order_id is not null and 
        @begin_date is not null and 
        @end_date is not null and 
        @stock_id is not null and 
        @type is not null
    begin
        select * from orders
            where user_id=@user_id and order_id=@order_id and stock_id=@stock_id 
                and type=@type and (create_date between @begin_date and @end_date)
    end
    else
    begin
    end
            
end