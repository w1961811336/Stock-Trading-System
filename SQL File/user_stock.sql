if(object_id('user_stock', 'P') is not null)
    drop procedure user_stock
go

create procedure user_stock
    @user_id bigint
as
begin
    select * from user_position where user_id=@user_id
end