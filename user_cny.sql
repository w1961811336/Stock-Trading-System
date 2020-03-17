if(object_id('user_cny', 'P') is not null)
    drop procedure user_cny
go
create procedure user_cny
    @user_id bigint, @cny_free money output, @cny_freezed money output,
    @asset money output
as
begin
    --存在查询两次问题
    
    declare @num_free int, @num_freezed int, @price int, @stock_id bigint;
    --当前用户拥有的总的股票价值
    declare @total_stock_value int;
    --如果该用户id不存在返回-1--
    if not exists(select *
                        from users
                        where user_id=@user_id)
        return -1
    
    --获取用户可用和冻结人民币的数量
    select @cny_free=cny_free, @cny_freezed=cny_freezed
        from users
        where user_id=@user_id
    
    --获取当前用户拥有的股票信息
    declare user_positions cursor for
        select stock_id, num_free, num_freezed
            from user_position
            where user_id=@user_id
            order by stock_id
    open user_positions
    --初始化总的股票价值
    set @total_stock_value = 0;
    --遍历用户拥有的股票
    while true
    begin
        fetch next from user_positions into
            @stock_id, @num_free, @num_freezed
        --若遍历完成，则退出循环
        if @@fetch_status != 0 break
        
        --可能存在price不存在的情况？
        select top(1) @price=price from transactions
            where stock_id=200001
            order by time desc
        --总的股票价值=每一个股票数量*最新成交的价格
        @total_stock_value = @total_stock_value + @price * (@num_free + @num_freezed)
    end
    --计算总资产：用户的人民币数量+持股数量*股票当前成交价格
    set @asset = @cny_free + @cny_freezed + @total_stock_value
    
    --查询成功返回0
    return 0
end