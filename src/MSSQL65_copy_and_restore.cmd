@echo off
rem Nome: MSSQL65_copy_and_restore.cmd
rem Objetivo: Manutibilidade de servidor legado MSSQL 6.5
rem Ele copia um arquivo de backup do MSSQL 6.5 para o
rem   drive local de uma maquina virtual que também tenha o MSSQL 6.5
rem   instalado e então faz um restore. Assim, testará se o 
rem   backup/restore funcionará em caso de sinistro.
rem Os nomes das variaveis sao autoexplicativas e que o admin use de 
rem   discernimento para compreendê-las.
rem TOOO: De alguma forma ainda tenho que ajustar porque a data entre
rem    o mais recente e o que eu restaurei da ultima vez nao esta 
rem    funcionando tao bem. A ideial inicial é que ele não restaure
rem    arquivo que já restaurou antes. Evitando recopiar o mesmo arquivo
rem    pois essas bases são grandes e tempo de restauração é demorado.
rem Visto que esta versão do MSSQL usa versão antiga do windows (Até 2003)
rem   então não posso fazer uso de outras linguagens ou comandos 
rem   encontrados em versões posteriores do windows e que me facilitariam
rem   a vida.
rem  
SETLOCAL ENABLEDELAYEDEXPANSION
cls
echo ======================================================================
echo =  Copiando o ultimo backup do servidor terra para este Servidor     =
echo ======================================================================
set backup_unc_as_letter=z:
set backup_server=terra
set backup_share=Backups
set backup_unc=\\%backup_server%\%backup_share%
set backup_unc_subdir=%backup_unc_as_letter%\backup-mssql
set backup_user=suporte
rem host, user, password do banco de dados de desenvolvimento
set mssql_isql=c:\mssql\binn\isql.exe
set mssql_dev_host=beta
set mssql_dev_db=VIDY
set mssql_dev_user=sa
set mssql_dev_pass=masterkey
set file_log=%temp%\restore.log
set file_ok=%temp%\restore.sql
set file_fail=%temp%\copy.fail.txt
set file_temp=%temp%\temp.~
rem set COPYCMD=/Y

rem remove drive Z: e o mapeia novamente segundo as credencias acima
echo Testando a existencia do drive %backup_unc_as_letter%, se existir desconectar ...
if exist %backup_unc_as_letter% net use %backup_unc_as_letter% /del >nul
echo Criando a unidade %backup_unc_as_letter% com base em %backup_unc%...
if not exist "%backup_unc_as_letter%" net use %backup_unc_as_letter% %backup_unc% /user:%backup_user% /persistent:yes >nul
if not exist "%backup_unc_as_letter%" goto notmap

rem === inicio ===
set origem20=%backup_unc_subdir%\backup_mssql.DAT
set origem12=%backup_unc_subdir%\backup_mssql_12h.DAT
set destino=c:\mssql\backup\backup_mssql.DAT
set xcopy_opt=/I /F /C /Y /D /Z
echo Testando qual o arquivo mais recente dentre: 
echo   %origem20% ^?
echo   %origem12% ^?
echo ...
FOR /F %%i IN ('DIR /B /O:D %origem20% %origem12%') DO SET origem=%backup_unc_subdir%\%%i
echo copiando o arquivo mais recente(origem):
echo %origem%
echo para(destino):
echo %destino%

set file_ok_msg=-- copia com sucesso de %origem%, vamos restaurar...
set file_fail_msg=Copia falhou ou nao foi necessario copiar porque o arquivo atual era mais recente.

if not exist "%origem%" goto notfound
if exist "%origem%" goto copiar
goto :fim

:notfound
  echo Nao existe arquivo: %origem%
goto :fim

:copiar
  if exist "%file_fail%" del /q /s "%file_fail%" >nul
  if exist "%file_ok%" del /q /s "%file_ok%" >nul
  if exist "%origem%" (
    echo F|xcopy %xcopy_opt% "%origem%" "%destino%" 
    set resultado=!!errorlevel!!
    echo resultado das copia = !!errorlevel!! isto significa que:
    if /I "!!resultado!!" equ "0" echo Arquivos foram copiados com sucesso.
    if /I "!!resultado!!" equ "0" echo %file_ok_msg% >"%file_ok%"

    if /I "!!resultado!!" equ "1" echo Nao haviam arquivos para serem copiados.
    if /I "!!resultado!!" equ "2" echo O usuario pressionou CTRL+C para abortar a operacao.
    if /I "!!resultado!!" equ "4" (
      echo Ocorreu um erro de inicializacao. Este erro nao trata-se
      echo   de falta de memoria ou espaço em disco, ou entrada letra
      echo   de drive invalido ou erro de sintaxe de linha de comando.
    )
    if /I "%resultado%" equ "5" echo Erro de escrita em disco, talvez disco cheio ou protegido.
    if not exist "%file_ok%" echo %file_fail_msg%>"%file_fail%"
    if exist "%file_ok%" goto check_restaurar
  )  
goto fim

:check_restaurar
  rem comparar se o ultimo restore for inferior a este arquivo de backup
  rem entao proceder com a restauracao
  set backup_file=%destino%
  for %%x in ("%backup_file%") do set date_last_backup=%%~tx
  rem formato de saida: 18/12/2019 11:16
  rem                   0123456789012345
  set year=%date_last_backup:~6,4%
  set month=%date_last_backup:~3,2%
  set day=%date_last_backup:~0,2%
  set hour=%date_last_backup:~11,2%
  set minute=%date_last_backup:~14,2%
  set date_last_backup=%year%%month%%day%%hour%%minute%
  echo Data do arquivo de backup: %date_last_backup%
  rem data do ultimo restore desse database
  echo ============================================================================
  echo detectando o ultimo restore %file_sql_get_last_restore%...
  echo ============================================================================  
  if exist "%file_temp%.sql" del /q /s "%file_temp%.sql" > nul
  echo criando o arquivo %file_temp%.sql com instrucoes SQL
  echo que retornam na ultima linha, quando foi o ultimo restore...
  echo set rowcount 1 >%file_temp%.sql
  echo set NOCOUNT on >>%file_temp%.sql
  echo declare @_restore_date varchar^(30^) >>%file_temp%.sql
  echo select @_restore_date = "197001010000" >>%file_temp%.sql
  echo if exists^(select * from master..sysdatabases where name = 'VIDY'^) >>%file_temp%.sql
  echo begin >>%file_temp%.sql
  echo   select @_restore_date= >>%file_temp%.sql
  echo     convert^(varchar^(30^),restore_date, 102^)+':'+convert^(varchar^(5^),restore_date, 114^) >>%file_temp%.sql
  echo   from msdb..sysrestorehistory >>%file_temp%.sql
  echo   order by restore_date desc >>%file_temp%.sql
  echo   set rowcount 0 >>%file_temp%.sql
  echo   print @_restore_date >>%file_temp%.sql
  echo   -- YYYY.MM.DD:HH:NN >>%file_temp%.sql
  echo   select @_restore_date=>>%file_temp%.sql
  echo     SUBSTRING^(@_restore_date,1,4^)+ >>%file_temp%.sql
  echo     SUBSTRING^(@_restore_date,6,2^)+ >>%file_temp%.sql
  echo     SUBSTRING^(@_restore_date,9,2^)+ >>%file_temp%.sql
  echo     SUBSTRING^(@_restore_date,12,2^)+ >>%file_temp%.sql
  echo     SUBSTRING^(@_restore_date,15,2^) >>%file_temp%.sql
  echo end >>%file_temp%.sql
  echo PRINT @_restore_date >>%file_temp%.sql
  rem type "%file_temp%.sql"
  echo executando-o...
  set mssql_cmd=%mssql_isql% -U %mssql_dev_user% -P %mssql_dev_pass% -S %mssql_dev_host% -i "%file_temp%.sql" -o "%file_temp%"
  %mssql_cmd%
  set resultado=!!errorlevel!!
  echo resultado da execuçao do script = !!resultado!!
  if exist "%file_temp%.sql" del /q /s "%file_temp%.sql" > nul

  rem removendo linhas vazias de "%file_temp%"
  for /f "usebackq tokens=* delims=" %%a in ("%file_temp%") do (echo(%%a)>>"%file_temp%.1"
  move /y  "%file_temp%.1" "%file_temp%" >nul

  rem pegando a ultima linha do arquivo "%file_temp%" que contem a data
  for /f "tokens=*" %%f in (!!file_temp!!) do set date_last_restore=%%f

  rem removendo os espaços
  set date_last_backup=!date_last_backup: =%%20!
  set date_last_restore=!date_last_restore: =%%20!

  rem apaga o arq temporario
  if exist "%file_temp%" del /q /s "%file_temp%" > nul
  
  echo Data do arquivo de backup: %date_last_backup% 
  echo Data do ultimo restore   : %date_last_restore%

  if "%date_last_backup%" gtr "%date_last_restore%" (
    echo Ultimo backup [%date_last_backup%] foi mais recente que o ultimo restore [%date_last_restore%], iniciando restauracao de %backup_file%...   
    goto restaurar
  ) else (
    echo Ultimo restore [%date_last_restore%] foi mais recente que o ultimo backup [%date_last_backup%], ignorando nova restauracao...
  )  
  goto fim  
goto fim

:restaurar
  echo ============================================================================
  echo Copia realizada com sucesso, vamos testar a restauracao....
  echo Restaurando database: "%destino%"
  echo Uso do script: "%file_ok%"
  echo ============================================================================
  echo LOAD DATABASE %mssql_dev_db% >>"%file_ok%"
  echo FROM BACKUP_MSSQL >>"%file_ok%"
  echo WITH NOUNLOAD ,  STATS = 5 >>"%file_ok%"
  echo GO >>"%file_ok%"
  echo ============================================================================
  echo Iniciando o processo de restauraçao, 
  echo NAO USE CTRL+C, senao corrompera o banco de dados %mssql_dev_db%
  set mssql_cmd=%mssql_isql% -U %mssql_dev_user% -P %mssql_dev_pass% -S %mssql_dev_host% -i "%file_ok%" 
  echo %mssql_cmd%
  echo ============================================================================
  rem type "%file_ok%"
  %mssql_cmd%
  set resultado=!!errorlevel!!
  echo resultado da restauracao do database '%mssql_dev_db%' = %resultado%  

  
  echo ============================================================================
  echo Preparando os logins existentes para funcionarem...
  echo ============================================================================
  if exist "%file_temp%" del /q /s "%file_temp%" >nul
  echo if exists^(select * from msdb..sysobjects where type = 'P' and name = 'SP_REBULD_DEV_LOGINS'^)>"%file_temp%"
  echo begin>>"%file_temp%"
  echo   exec msdb..SP_REBULD_DEV_LOGINS>>"%file_temp%"
  echo end>>"%file_temp%"

  set mssql_cmd=%mssql_isql% -U %mssql_dev_user% -P %mssql_dev_pass% -S %mssql_dev_host% -i "%file_temp%" 
  echo %mssql_cmd%
  %mssql_cmd%
  set resultado=!!errorlevel!!
  echo resultado da execuçao do script = %resultado%  

  echo ============================================================================
  echo Apresentando as restauraçao nos ultimos 5 dias
  echo ============================================================================
  if exist "%file_log%" del /q /s "%file_log%"
  echo -- Para conferir os backups/restores dos ultimos 5 dias>"%file_ok%"
  echo select a.backup_start, a.backup_finish, a.restore_date>>"%file_ok%"
  echo from msdb..sysrestorehistory a>>"%file_ok%"
  echo where >>"%file_ok%"
  echo       (a.source_database_name = '%mssql_dev_db%')>>"%file_ok%"
  echo   AND (a.restore_date ^>= DATEADD(DAY, -5, GETDATE()))>>"%file_ok%"
  echo order by restore_date DESC>>"%file_ok%"
  echo GO >>"%file_ok%"
  set mssql_cmd=%mssql_isql% -U %mssql_dev_user% -P %mssql_dev_pass% -S %mssql_dev_host% -i "%file_ok%" -o "%file_log%"
  %mssql_cmd%
  set resultado=!!errorlevel!!
  echo resultado da execuçao do script = %resultado%  

  if exist "%file_log%" (
    type "%file_ok%"
    type "%file_log%"
  )  
  if exist "%file_ok%" del /q /s "%file_ok%"

goto fim

:notmap
  echo ========================================================================
  echo O mapeamento falhou, por gentileza execute manualmente no cmd:
  echo cmdkey /add:%backup_server% /user:%backup_server%\%backup_user% /pass:SENHA
  echo ou 
  echo net use %backup_server% /SAVECRED
  echo (exemplo acima a senha sera questionada)
  echo Em ambos os casos a senha será memorizada e será possivel utiliza-la 
  echo na proxima vez que este script for executado sem a necessidade de digia-la.
  echo ========================================================================
goto fim

:fim
  echo desconectando %backup_unc_as_letter% ...
  if exist %backup_unc_as_letter% net use %backup_unc_as_letter% /del >nul
REM pause
