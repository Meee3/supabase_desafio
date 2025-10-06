import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
serve(async (req)=>{
  try {
    const { pedido_id } = await req.json();
    const supabaseClient = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_ANON_KEY') ?? '', {
      global: {
        headers: {
          Authorization: req.headers.get('Authorization')
        }
      }
    });
    const { data: detalhesPedido, error } = await supabaseClient.from('detalhes_pedido').select('*').eq('pedido_id', pedido_id);
    if (error) throw error;
    if (!detalhesPedido || detalhesPedido.length === 0) {
      return new Response(JSON.stringify({
        erro: 'Pedido não encontrado'
      }), {
        status: 404,
        headers: {
          'Content-Type': 'application/json'
        }
      });
    }
    const pedido = detalhesPedido[0];
    const itens = detalhesPedido;
    const emailHtml = `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: #4CAF50; color: white; padding: 20px; text-align: center; }
          .content { padding: 20px; background: #f9f9f9; }
          .info-pedido { background: white; padding: 15px; margin: 10px 0; }
          .itens { margin: 20px 0; }
          .item { padding: 10px; border-bottom: 1px solid #ddd; }
          .total { font-size: 1.2em; font-weight: bold; text-align: right; margin-top: 20px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>✅ Pedido Confirmado!</h1>
          </div>
          <div class="content">
            <div class="info-pedido">
              <p><strong>Número do Pedido:</strong> ${pedido.pedido_id.substring(0, 8).toUpperCase()}</p>
              <p><strong>Data:</strong> ${new Date(pedido.data_pedido).toLocaleDateString('pt-BR')}</p>
              <p><strong>Status:</strong> ${pedido.status.toUpperCase()}</p>
            </div>
            
            <div class="itens">
              <h2>Itens do Pedido:</h2>
              ${itens.map((item)=>`
                <div class="item">
                  <strong>${item.nome_produto}</strong><br>
                  Quantidade: ${item.quantidade} x R$ ${item.preco_unitario.toFixed(2)} = R$ ${item.subtotal.toFixed(2)}
                </div>
              `).join('')}
            </div>
            
            <div class="total">
              Total: R$ ${pedido.valor_total.toFixed(2)}
            </div>
            
            <p style="margin-top: 30px;">Obrigado pela sua compra! 🎉</p>
          </div>
        </div>
      </body>
      </html>
    `;
    console.log('📧 Email preparado para:', pedido.email_cliente);
    console.log('Assunto:', `Pedido Confirmado #${pedido.pedido_id.substring(0, 8)}`);
    return new Response(JSON.stringify({
      sucesso: true,
      mensagem: 'Confirmação processada',
      pedido: pedido.pedido_id,
      cliente: pedido.email_cliente
    }), {
      headers: {
        'Content-Type': 'application/json'
      },
      status: 200
    });
  } catch (erro) {
    return new Response(JSON.stringify({
      erro: erro.message
    }), {
      headers: {
        'Content-Type': 'application/json'
      },
      status: 400
    });
  }
});
