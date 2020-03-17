if (object_id('user_login', 'P') is not null)
    drop procedure user_login
go
create procedure user_login 
    @login_name nchar(10), @passwd nchar(10), 
	@user_id bigint output, @name nchar(10) output, @type int output
as
begin
    --存在查询两次问题
    if not exists(select * from users
                    where login_name=@login_name and passwd=@passwd)
        return -1
    else
    begin
        select @user_id=user_id, @name=name, @type=type
        from users
        where login_name=@login_name and passwd=@passwd
        return 0
    end
    
end
