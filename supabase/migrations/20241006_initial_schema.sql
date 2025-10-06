CREATE TABLE clientes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    nome_completo VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    telefone VARCHAR(20),
    endereco JSONB,
    -- {rua, cidade, estado, cep, pais}
    criado_em TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    atualizado_em TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE TABLE produtos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome VARCHAR(255) NOT NULL,
    descricao TEXT,
    preco DECIMAL(10, 2) NOT NULL CHECK (preco >= 0),
    quantidade_estoque INTEGER NOT NULL DEFAULT 0 CHECK (quantidade_estoque >= 0),
    categoria VARCHAR(100),
    url_imagem TEXT,
    ativo BOOLEAN DEFAULT true,
    criado_em TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    atualizado_em TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE TABLE pedidos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cliente_id UUID REFERENCES clientes(id) ON DELETE CASCADE NOT NULL,
    status VARCHAR(50) DEFAULT 'pendente' CHECK (
        status IN (
            'pendente',
            'confirmado',
            'enviado',
            'entregue',
            'cancelado'
        )
    ),
    valor_total DECIMAL(10, 2) DEFAULT 0 CHECK (valor_total >= 0),
    endereco_entrega JSONB,
    observacoes TEXT,
    criado_em TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    atualizado_em TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE TABLE itens_pedido (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pedido_id UUID REFERENCES pedidos(id) ON DELETE CASCADE NOT NULL,
    produto_id UUID REFERENCES produtos(id) ON DELETE RESTRICT NOT NULL,
    quantidade INTEGER NOT NULL CHECK (quantidade > 0),
    preco_unitario DECIMAL(10, 2) NOT NULL CHECK (preco_unitario >= 0),
    subtotal DECIMAL(10, 2) GENERATED ALWAYS AS (quantidade * preco_unitario) STORED,
    criado_em TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
-- ============================================
-- HABILITAR RLS EM TODAS AS TABELAS
-- ============================================
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE produtos ENABLE ROW LEVEL SECURITY;
ALTER TABLE pedidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE itens_pedido ENABLE ROW LEVEL SECURITY;
-- ============================================
-- POLÍTICAS RLS: clientes
-- ============================================
-- Clientes podem ver apenas seus próprios dados
CREATE POLICY "Clientes podem visualizar seus proprios dados" ON clientes FOR
SELECT USING (auth.uid() = usuario_id);
-- Clientes podem atualizar apenas seus próprios dados
CREATE POLICY "Clientes podem atualizar seus proprios dados" ON clientes FOR
UPDATE USING (auth.uid() = usuario_id);
-- Permitir inserção ao criar conta
CREATE POLICY "Usuarios podem inserir seu proprio registro" ON clientes FOR
INSERT WITH CHECK (auth.uid() = usuario_id);
-- ============================================
-- POLÍTICAS RLS: produtos
-- ============================================
-- Todos podem visualizar produtos ativos (para catálogo público)
CREATE POLICY "Qualquer um pode visualizar produtos ativos" ON produtos FOR
SELECT USING (ativo = true);
-- Apenas administradores podem inserir/atualizar/deletar produtos
CREATE POLICY "Apenas admins podem gerenciar produtos" ON produtos FOR ALL USING (
    EXISTS (
        SELECT 1
        FROM auth.users
        WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'funcao' = 'admin'
    )
);
-- ============================================
-- POLÍTICAS RLS: pedidos
-- ============================================
-- Clientes podem ver apenas seus próprios pedidos
CREATE POLICY "Clientes podem visualizar seus proprios pedidos" ON pedidos FOR
SELECT USING (
        EXISTS (
            SELECT 1
            FROM clientes
            WHERE clientes.id = pedidos.cliente_id
                AND clientes.usuario_id = auth.uid()
        )
    );
-- Clientes podem criar seus próprios pedidos
CREATE POLICY "Clientes podem criar seus proprios pedidos" ON pedidos FOR
INSERT WITH CHECK (
        EXISTS (
            SELECT 1
            FROM clientes
            WHERE clientes.id = pedidos.cliente_id
                AND clientes.usuario_id = auth.uid()
        )
    );
-- Apenas admins podem atualizar status de pedidos
CREATE POLICY "Apenas admins podem atualizar status do pedido" ON pedidos FOR
UPDATE USING (
        EXISTS (
            SELECT 1
            FROM auth.users
            WHERE auth.users.id = auth.uid()
                AND auth.users.raw_user_meta_data->>'funcao' = 'admin'
        )
    );
-- ============================================
-- POLÍTICAS RLS: itens_pedido
-- ============================================
-- Clientes podem ver itens de seus próprios pedidos
CREATE POLICY "Clientes podem visualizar itens de seus proprios pedidos" ON itens_pedido FOR
SELECT USING (
        EXISTS (
            SELECT 1
            FROM pedidos
                JOIN clientes ON clientes.id = pedidos.cliente_id
            WHERE pedidos.id = itens_pedido.pedido_id
                AND clientes.usuario_id = auth.uid()
        )
    );
-- Clientes podem adicionar itens aos seus próprios pedidos
CREATE POLICY "Clientes podem adicionar itens aos seus proprios pedidos" ON itens_pedido FOR
INSERT WITH CHECK (
        EXISTS (
            SELECT 1
            FROM pedidos
                JOIN clientes ON clientes.id = pedidos.cliente_id
            WHERE pedidos.id = itens_pedido.pedido_id
                AND clientes.usuario_id = auth.uid()
        )
    );
CREATE OR REPLACE FUNCTION atualizar_coluna_atualizado_em() RETURNS TRIGGER AS $$ BEGIN NEW.atualizado_em = NOW();
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- Aplicar trigger em todas as tabelas relevantes
CREATE TRIGGER atualizar_clientes_atualizado_em BEFORE
UPDATE ON clientes FOR EACH ROW EXECUTE FUNCTION atualizar_coluna_atualizado_em();
CREATE TRIGGER atualizar_produtos_atualizado_em BEFORE
UPDATE ON produtos FOR EACH ROW EXECUTE FUNCTION atualizar_coluna_atualizado_em();
CREATE TRIGGER atualizar_pedidos_atualizado_em BEFORE
UPDATE ON pedidos FOR EACH ROW EXECUTE FUNCTION atualizar_coluna_atualizado_em();
-- ============================================
-- FUNÇÃO: Calcular total do pedido
-- ============================================
CREATE OR REPLACE FUNCTION calcular_total_pedido(pedido_id_param UUID) RETURNS DECIMAL AS $$
DECLARE total DECIMAL(10, 2);
BEGIN
SELECT COALESCE(SUM(subtotal), 0) INTO total
FROM itens_pedido
WHERE pedido_id = pedido_id_param;
RETURN total;
END;
$$ LANGUAGE plpgsql;
-- ============================================
-- FUNÇÃO: Atualizar total do pedido automaticamente
-- ============================================
CREATE OR REPLACE FUNCTION atualizar_total_pedido() RETURNS TRIGGER AS $$ BEGIN -- Atualizar o total do pedido quando itens são adicionados/modificados/removidos
UPDATE pedidos
SET valor_total = calcular_total_pedido(
        CASE
            WHEN TG_OP = 'DELETE' THEN OLD.pedido_id
            ELSE NEW.pedido_id
        END
    )
WHERE id = CASE
        WHEN TG_OP = 'DELETE' THEN OLD.pedido_id
        ELSE NEW.pedido_id
    END;
RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
-- Trigger para atualizar total automaticamente
CREATE TRIGGER trigger_atualizar_total_pedido
AFTER
INSERT
    OR
UPDATE
    OR DELETE ON itens_pedido FOR EACH ROW EXECUTE FUNCTION atualizar_total_pedido();
-- ============================================
-- FUNÇÃO: Verificar e atualizar estoque
-- ============================================
CREATE OR REPLACE FUNCTION verificar_e_atualizar_estoque() RETURNS TRIGGER AS $$ BEGIN -- Verificar se há estoque suficiente
    IF (
        SELECT quantidade_estoque
        FROM produtos
        WHERE id = NEW.produto_id
    ) < NEW.quantidade THEN RAISE EXCEPTION 'Estoque insuficiente para o produto';
END IF;
-- Reduzir estoque ao criar item do pedido
UPDATE produtos
SET quantidade_estoque = quantidade_estoque - NEW.quantidade
WHERE id = NEW.produto_id;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trigger_verificar_estoque BEFORE
INSERT ON itens_pedido FOR EACH ROW EXECUTE FUNCTION verificar_e_atualizar_estoque();
-- ============================================
-- FUNÇÃO: Atualizar status do pedido
-- ============================================
CREATE OR REPLACE FUNCTION atualizar_status_pedido(
        pedido_id_param UUID,
        novo_status VARCHAR(50)
    ) RETURNS VOID AS $$ BEGIN -- Validar status
    IF novo_status NOT IN (
        'pendente',
        'confirmado',
        'enviado',
        'entregue',
        'cancelado'
    ) THEN RAISE EXCEPTION 'Status inválido';
END IF;
-- Atualizar status
UPDATE pedidos
SET status = novo_status,
    atualizado_em = NOW()
WHERE id = pedido_id_param;
-- Se cancelado, devolver estoque
IF novo_status = 'cancelado' THEN
UPDATE produtos p
SET quantidade_estoque = quantidade_estoque + ip.quantidade
FROM itens_pedido ip
WHERE ip.pedido_id = pedido_id_param
    AND ip.produto_id = p.id;
END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- ============================================
-- FUNÇÃO: Criar pedido completo
-- ============================================
CREATE OR REPLACE FUNCTION criar_pedido(
        cliente_id_param UUID,
        itens JSONB,
        -- [{produto_id: uuid, quantidade: int}]
        endereco_entrega_param JSONB,
        observacoes_param TEXT DEFAULT NULL
    ) RETURNS UUID AS $$
DECLARE novo_pedido_id UUID;
item JSONB;
preco_produto DECIMAL(10, 2);
BEGIN -- Criar o pedido
INSERT INTO pedidos (cliente_id, endereco_entrega, observacoes)
VALUES (
        cliente_id_param,
        endereco_entrega_param,
        observacoes_param
    )
RETURNING id INTO novo_pedido_id;
-- Adicionar itens ao pedido
FOR item IN
SELECT *
FROM jsonb_array_elements(itens) LOOP -- Buscar preço atual do produto
SELECT preco INTO preco_produto
FROM produtos
WHERE id = (item->>'produto_id')::UUID
    AND ativo = true;
IF preco_produto IS NULL THEN RAISE EXCEPTION 'Produto não encontrado ou inativo';
END IF;
-- Inserir item do pedido
INSERT INTO itens_pedido (
        pedido_id,
        produto_id,
        quantidade,
        preco_unitario
    )
VALUES (
        novo_pedido_id,
        (item->>'produto_id')::UUID,
        (item->>'quantidade')::INTEGER,
        preco_produto
    );
END LOOP;
RETURN novo_pedido_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- ============================================
-- VIEW: Resumo de pedidos com informações do cliente
-- ============================================
CREATE OR REPLACE VIEW resumo_pedidos AS
SELECT p.id AS pedido_id,
    p.status,
    p.valor_total,
    p.criado_em AS data_pedido,
    c.id AS cliente_id,
    c.nome_completo AS nome_cliente,
    c.email AS email_cliente,
    COUNT(ip.id) AS total_itens,
    SUM(ip.quantidade) AS quantidade_total
FROM pedidos p
    JOIN clientes c ON c.id = p.cliente_id
    LEFT JOIN itens_pedido ip ON ip.pedido_id = p.id
GROUP BY p.id,
    p.status,
    p.valor_total,
    p.criado_em,
    c.id,
    c.nome_completo,
    c.email;
-- ============================================
-- VIEW: Detalhes completos do pedido
-- ============================================
CREATE OR REPLACE VIEW detalhes_pedido AS
SELECT p.id AS pedido_id,
    p.status,
    p.valor_total,
    p.criado_em AS data_pedido,
    p.endereco_entrega,
    c.nome_completo AS nome_cliente,
    c.email AS email_cliente,
    c.telefone AS telefone_cliente,
    ip.id AS item_id,
    pr.nome AS nome_produto,
    pr.url_imagem AS imagem_produto,
    ip.quantidade,
    ip.preco_unitario,
    ip.subtotal
FROM pedidos p
    JOIN clientes c ON c.id = p.cliente_id
    JOIN itens_pedido ip ON ip.pedido_id = p.id
    JOIN produtos pr ON pr.id = ip.produto_id;
-- ============================================
-- VIEW: Produtos mais vendidos
-- ============================================
CREATE OR REPLACE VIEW produtos_mais_vendidos AS
SELECT pr.id,
    pr.nome,
    pr.categoria,
    pr.preco,
    COUNT(ip.id) AS vezes_pedido,
    SUM(ip.quantidade) AS total_vendido,
    SUM(ip.subtotal) AS receita_total
FROM produtos pr
    JOIN itens_pedido ip ON ip.produto_id = pr.id
    JOIN pedidos p ON p.id = ip.pedido_id
WHERE p.status != 'cancelado'
GROUP BY pr.id,
    pr.nome,
    pr.categoria,
    pr.preco
ORDER BY total_vendido DESC;
-- ============================================
-- VIEW: Histórico de compras do cliente
-- ============================================
CREATE OR REPLACE VIEW historico_compras_cliente AS
SELECT c.id AS cliente_id,
    c.nome_completo,
    c.email,
    COUNT(DISTINCT p.id) AS total_pedidos,
    SUM(p.valor_total) AS valor_total_vida,
    MAX(p.criado_em) AS data_ultimo_pedido,
    AVG(p.valor_total) AS valor_medio_pedido
FROM clientes c
    LEFT JOIN pedidos p ON p.cliente_id = c.id
WHERE p.status != 'cancelado'
    OR p.status IS NULL
GROUP BY c.id,
    c.nome_completo,
    c.email;
SELECT *
FROM produtos
LIMIT 5;
-- Se não tiver, inserir produtos de teste
INSERT INTO produtos (
        nome,
        descricao,
        preco,
        quantidade_estoque,
        categoria,
        ativo
    )
VALUES (
        'Notebook Dell',
        'Notebook Dell Inspiron 15',
        3500.00,
        10,
        'Eletrônicos',
        true
    ),
    (
        'Mouse Logitech',
        'Mouse sem fio',
        350.00,
        50,
        'Acessórios',
        true
    )
RETURNING id;
-- Primeiro, crie um cliente (você precisa ter um usuário autenticado)
-- Ou use este script simplificado para teste:
DO $$
DECLARE cliente_id UUID;
produto1_id UUID;
pedido_id UUID;
BEGIN -- Criar cliente de teste
INSERT INTO clientes (nome_completo, email, telefone, endereco)
VALUES (
        'João Silva Teste',
        'joao.teste@email.com',
        '16999999999',
        '{"rua": "Rua Teste, 123", "cidade": "São Carlos", "estado": "SP", "cep": "13560-000"}'::jsonb
    )
RETURNING id INTO cliente_id;
-- Pegar ID de um produto
SELECT id INTO produto1_id
FROM produtos
WHERE ativo = true
LIMIT 1;
-- Criar pedido usando a função
SELECT criar_pedido(
        cliente_id,
        jsonb_build_array(
            jsonb_build_object('produto_id', produto1_id, 'quantidade', 2)
        ),
        '{"rua": "Rua Teste, 123", "cidade": "São Carlos", "estado": "SP"}'::jsonb,
        'Pedido de teste'
    ) INTO pedido_id;
-- Mostrar o ID do pedido criado
RAISE NOTICE 'Pedido criado: %',
pedido_id;
END $$;